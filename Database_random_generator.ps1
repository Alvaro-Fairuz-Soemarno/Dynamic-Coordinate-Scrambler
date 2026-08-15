$port = 8000
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "PowerShell Server started on http://localhost:$port/"
Write-Host "Waiting for requests..."

$ServerName = "localhost\SQLEXPRESS"
$DatabaseName = "Coordinate_Registry"

$ConnectionString = "Server=$ServerName;Database=$DatabaseName;Integrated Security=True;"

# Helper Function to Generate Specific Coordinate Components
function Get-RandomCoordinateComponent {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateSet("Longitude", "Latitude", "Altitude")]
        [string]$Type
    )

    # Set specific ranges based on the coordinate type
    switch ($Type) {
        "Longitude" { $Min = -180.0; $Max = 180.0 }
        "Latitude" { $Min = -90.0; $Max = 90.0 }
        "Altitude" { $Min = -400.0; $Max = 8848.0 } # Example range in meters (Dead Sea to Mt. Everest)
    }

    # Generate raw value
    $RawValue = Get-Random -Minimum $Min -Maximum $Max
    
    # Select dynamic decimal places from 1 to 7
    $RandomDecimals = Get-Random -Minimum 1 -Maximum 8
    
    # Return the rounded value
    return [Math]::Round($RawValue, $RandomDecimals)
}

# Consolidated Address Helper Function
function Get-RandomFullAddress {
    $Streets = @("Main St", "Oak Ave", "Pine Rd", "Maple Dr", "Cedar Ln", "Elm St", "Broadway", "Washington St")
    $Cities = @("Seattle", "Chicago", "Austin", "Denver", "Boston", "Atlanta", "New York", "San Francisco")

    $Number = Get-Random -Minimum 100 -Maximum 9999
    $Street = $Streets | Get-Random
    $City = $Cities | Get-Random
    $Zip = Get-Random -Minimum 10000 -Maximum 99999

    # Compacted format: "1234 Main St, Seattle, 98101"
    return "$Number $Street, $City, $Zip"
}

try {
    # 3. Initialize native .NET SQL Connection
    $Connection = New-Object System.Data.SqlClient.SqlConnection
    $Connection.ConnectionString = $ConnectionString
    $Connection.Open()

    # 4. Parameterized Query with compacted FullAddress column
    $InsertQuery = "INSERT INTO REGISTERED_COORDINATES_LIST (Latitude, Longitude, Altitude, FullAddress) VALUES (@Lat, @Lon, @Alt, @Address);"
    
    $SuccessfullyInserted = 0
    while ($SuccessfullyInserted -lt 300) {
        
        # Call the separated functions for each coordinate type
        $Latitude = Get-RandomCoordinateComponent -Type "Latitude"
        $Longitude = Get-RandomCoordinateComponent -Type "Longitude"
        $Altitude = Get-RandomCoordinateComponent -Type "Altitude"

        # Generate the single, compacted address string
        $FullAddress = Get-RandomFullAddress

        # 5. Build and execute SqlCommand
        $Command = New-Object System.Data.SqlClient.SqlCommand($InsertQuery, $Connection)
        $Command.Parameters.AddWithValue("@Lat", $Latitude) | Out-Null
        $Command.Parameters.AddWithValue("@Lon", $Longitude) | Out-Null
        $Command.Parameters.AddWithValue("@Alt", $Altitude) | Out-Null
        $Command.Parameters.AddWithValue("@Address", $FullAddress) | Out-Null
        
        try {
            $Command.ExecuteNonQuery() | Out-Null
            $SuccessfullyInserted++ # Only counts if the insert actually worked!
            Write-Host "Inserted ($SuccessfullyInserted/300): Lon: $Longitude, Lat: $Latitude, Alt: $Altitude | Address: $FullAddress"
        }
        catch {
            if ($_.Exception.Message -match "UNIQUE" -or $_.Exception.Message -match "PRIMARY") {
                Write-Host "Duplicate found! Skipping..." -ForegroundColor Yellow
            }
            else {
                throw $_ # Stops the script if it's a real database crash
            }
        }
    }

    Write-Host "Data generation and insertion complete!" -ForegroundColor Green
}
catch {
    Write-Error "Database Error: $_"
}
finally {
    # 6. Safety check to ensure connection closure
    if ($Connection -and $Connection.State -eq [System.Data.ConnectionState]::Open) {
        $Connection.Close()
        Write-Host "SQL Connection securely closed."
    }
}
