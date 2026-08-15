
$port = "8080"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "PowerShell API Server running on http://localhost:$port/" -ForegroundColor Green
Write-Host "Waiting for requests..." -ForegroundColor Yellow

# SQL Server Configuration 
$ServerName = "localhost\SQLEXPRESS"
$DatabaseName = "Coordinate_Registry"
$ConnectionString = "Server=$ServerName;Database=$DatabaseName;Integrated Security=True;"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # Inject CORS headers so browser HTML file can communicate across local ports safely
    $response.Headers.Add("Access-Control-Allow-Origin", "*")
    $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $response.Headers.Add("Access-Control-Allow-Methods", "POST, OPTIONS")

    # Handle preflight OPTIONS requests
    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 200
        $response.Close()
        continue
    }

    # =========================================================================
    # ENDPOINT 1: FETCH ORIGINAL PRIVATE COORDINATES (/get-private-coordinates)
    # =========================================================================
    if ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/get-private-coordinates") {
        $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
        $body = $reader.ReadToEnd()
        $dataInput = ConvertFrom-Json $body
        $targetAddress = $dataInput.address

        #Ensures system can fetch if there is total character mismatch between input and database using a safe trailing wildcard
        $SqlQuery = " SELECT Latitude, Longitude, Altitude FROM PRIVATE_COORDINATES_LIST WHERE FullAddress LIKE @Address +'%'"
        $SqlConnection = New-Object System.Data.SqlClient.SqlConnection($ConnectionString)
        $SqlCommand = New-Object System.Data.SqlClient.SqlCommand($SqlQuery, $SqlConnection)
        $SqlCommand.Parameters.AddWithValue("@Address", $targetAddress) | Out-Null

    
        
         try {
            $SqlConnection.Open()
            $SqlReader = $SqlCommand.ExecuteReader()
            if ($SqlReader.Read()) {
                $outputData = @{
                    status = "success"
                    lat = $SqlReader["Latitude"].ToString().Trim()
                    long = $SqlReader["Longitude"].ToString().Trim()
                    alt = $SqlReader["Altitude"].ToString().Trim()
                }
            Write-Host "Address found in SQL database" -ForegroundColor Green
            } else {
                $outputData = @{ status = "not_found"; message = "Address not found in SQL database" }
                Write-Host "Address not found in SQL database" -ForegroundColor Red
            }
        } catch {
            $outputData = @{ status = "error"; message = $_.Exception.Message }
        } finally {
            $SqlConnection.Close()
        }

        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json $outputData))
        $response.ContentType = "application/json"
        $response.ContentLength64 = $responseBytes.Length
        $response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
    } 


    # =========================================================================
    # ENDPOINT 2: CHECK FOR DUPLICATE TRIPLET (/check-duplicate-triplet)
    # =========================================================================
    elseif ($request.HttpMethod -eq "POST" -and $request.Url.LocalPath -eq "/check-duplicate-triplet") {
        $reader = New-Object System.IO.StreamReader($request.InputStream)
        $body = $reader.ReadToEnd()
        $dataInput = ConvertFrom-Json $body

        # Query matching the combined triplet pattern across all three columns
        $SqlQuery = "SELECT COUNT(*) FROM PRIVATE_COORDINATES_LIST WHERE Latitude = @Lat AND Longitude = @Long AND Altitude = @Alt"
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
    
    # =========================================================================
    # FALLBACK: ROUTE NOT FOUND (404)
    # =========================================================================
    else {
        $response.StatusCode = 404
    }
    
    $response.Close()
}
