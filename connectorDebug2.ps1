# Run this script inside PowerShell 5.1 as an Administrator
$port = "8080"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "PowerShell API Server running on http://localhost:$port/" -ForegroundColor Green

# SQL Server Configuration 
$ServerName = "localhost\SQLEXPRESS"
$DatabaseName = "Coordinate_Registry"
$ConnectionString = "Server=$ServerName;Database=$DatabaseName;Integrated Security=True;"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # Inject CORS headers so file can communicate across local ports safely
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $response.Headers.Add("Access-Control-Allow-Methods", "POST, OPTIONS")

    # Handle preflight OPTIONS requests
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        continue
    }

    # ENDPOINT 1: FETCH ORIGINAL COORDINATES (/get-coordinates)
    if ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/get-coordinates") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd()
        $dataInput = ConvertFrom-Json $body
        $targetAddress = $dataInput.address

     # DIAGNOSTIC LOG 1: What is PowerShell receiving from web browser?
        Write-Host "`n=== INCOMING REQUEST DEBUG ===" -ForegroundColor Cyan
        Write-Host "Received Address String: '$targetAddress'" -ForegroundColor Yellow
        Write-Host "Total Character Length : $($targetAddress.Length)" -ForegroundColor Yellow
    
    # Print the exact character array bytes to reveal hidden tabs, non-breaking spaces, or linebreaks
       $charBytes = [System.Text.Encoding]::UTF8.GetBytes($targetAddress)
       Write-Host "Raw Byte Array (UTF8) : $($charBytes -join ', ')" -ForegroundColor Gray


        $SqlQuery = " SELECT Latitude, Longitude, Altitude FROM REGISTERED_COORDINATES_LIST WHERE FullAddress LIKE @Address +'%'"
            
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $SqlCommand = New-Object System.Data.SqlClient.SqlCommand($SqlQuery, $SqlConnection)
        $SqlCommand.Parameters.AddWithValue("@Address", $targetAddress) | Out-Null

    
        
         try {
            $SqlConnection.Open()
            $SqlReader = $SqlCommand.ExecuteReader()
            
            if ($SqlReader.Read()) {
                Write-Host "SQL Match Found on absolute string!" -ForegroundColor Green
                $outputData = @{
                    status = "success"
                    lat = $SqlReader["Latitude"].ToString().Trim()
                    long = $SqlReader["Longitude"].ToString().Trim()
                    alt = $SqlReader["Altitude"].ToString().Trim()
                }
            } else {
                Write-Host "SQL Exact Match Failed. Running dynamic database search fallback..." -ForegroundColor Red
                $SqlReader.Close()

                # DIAGNOSTIC LOG 2: Dynamically split the query into pieces to see what's in the DB
                # Grabs the first distinct word or number from input (e.g., '112' or 'Mercer')
                $searchKeywords = $targetAddress.Split(@(' ', ','), [System.StringSplitOptions]::RemoveEmptyEntries)
                $firstKeyword = if ($searchKeywords.Count -gt 0) { $searchKeywords[0] } else { "" }
                
                Write-Host "--- Scanning database for entries containing '$firstKeyword' ---" -ForegroundColor Cyan
                
                $DebugQuery = "SELECT FullAddress FROM REGISTERED_COORDINATES_LIST WHERE FullAddress LIKE '%' + @Keyword + '%'"
                $DebugCmd = New-Object System.Data.SqlClient.SqlCommand($DebugQuery, $SqlConnection)
                $DebugCmd.Parameters.AddWithValue("@Keyword", $firstKeyword) | Out-Null
                $DebugReader = $DebugCmd.ExecuteReader()
                
                $foundAny = $false
                while ($DebugReader.Read()) {
                    $foundAny = $true
                    $dbAddress = $DebugReader["FullAddress"].ToString()
                    Write-Host "Found in DB : '$dbAddress'" -ForegroundColor Magenta
                    Write-Host "DB String Length : $($dbAddress.Length)" -ForegroundColor Magenta
                    
                    $dbBytes = [System.Text.Encoding]::UTF8.GetBytes($dbAddress)
                    Write-Host "DB Raw Byte Array (UTF8): $($dbBytes -join ', ')" -ForegroundColor Gray
                }
                $DebugReader.Close()
                
                if (-not $foundAny) {
                    Write-Host "Warning: No records matching the keyword '$firstKeyword' were found in your table row at all." -ForegroundColor Red
                }

                $outputData = @{ status = "not_found"; message = "Address not found in SQL database" }
            }
        } catch {
            Write-Host "SQL Exception Occurred: $_" -ForegroundColor DarkRed
            $outputData = @{ status = "error"; message = $_.Exception.Message }
        } finally {
            $SqlConnection.Close()
            Write-Host "==============================`n" -ForegroundColor Cyan
        }

        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $outputData))
        $response.ContentType = "application/json"
        $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
    }


    # ENDPOINT 2: CHECK FOR DUPLICATE TRIPLET (/check-duplicate-triplet)
    elseif ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/check-duplicate-triplet") {
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $body = $reader.ReadToEnd()
        $dataInput = ConvertFrom-Json $body

        # Query matching the combined triplet pattern across all three columns
        $SqlQuery = "SELECT COUNT(*) FROM REGISTERED_COORDINATES_LIST WHERE Latitude = @Lat AND Longitude = @Long AND Altitude = @Alt"
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $SqlCommand = New-Object System.Data.SqlClient.SqlCommand($SqlQuery, $SqlConnection)
        $SqlCommand.Parameters.AddWithValue("@Lat", $dataInput.lat) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@Long", $dataInput.long) | Out-Null
        $SqlCommand.Parameters.AddWithValue("@Alt", $dataInput.alt) | Out-Null

        try {
            $SqlConnection.Open()
            $RecordCount = $SqlCommand.ExecuteScalar()
            $isRegistered = $RecordCount -gt 0
            $outputData = @{ isRegistered = $isRegistered }
        } catch {
            $outputData = @{ isRegistered = $false; error = $_.Exception.Message }
        } finally {
            $SqlConnection.Close()
        }

        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $outputData))
        $response.ContentType = "application/json"
        $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
    }
    
    # FALLBACK: ROUTE NOT FOUND (404)
    else {
        $response.StatusCode = 404
    }
    
    $response.Close()
}
