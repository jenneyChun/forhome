param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
$ClientRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "code"))
$LogDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "log"))

function Write-AppLog($Message) {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    Add-Content -Path (Join-Path $LogDir "server.log") -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

function Get-ReasonPhrase($Status) {
    switch ($Status) {
        200 { "OK" }
        204 { "No Content" }
        404 { "Not Found" }
        405 { "Method Not Allowed" }
        410 { "Gone" }
        500 { "Internal Server Error" }
        default { "OK" }
    }
}

function Send-Bytes($Client, $Status, $ContentType, [byte[]]$Bytes) {
    $stream = $Client.GetStream()
    $reason = Get-ReasonPhrase $Status
    $headers = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Headers: Content-Type`r`nAccess-Control-Allow-Methods: GET, OPTIONS`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Bytes.Length -gt 0) {
        $stream.Write($Bytes, 0, $Bytes.Length)
    }
}

function Send-Text($Client, $Status, $ContentType, $Text) {
    if ($null -eq $Text) { $Text = "" }
    Send-Bytes $Client $Status $ContentType ([System.Text.Encoding]::UTF8.GetBytes($Text))
}

function Send-Json($Client, $Status, $Object) {
    Send-Text $Client $Status "application/json; charset=utf-8" ($Object | ConvertTo-Json -Depth 20)
}

function Find-HeaderEnd([byte[]]$Bytes) {
    if ($Bytes.Length -lt 4) { return -1 }
    for ($i = 0; $i -le $Bytes.Length - 4; $i++) {
        if ($Bytes[$i] -eq 13 -and $Bytes[$i + 1] -eq 10 -and $Bytes[$i + 2] -eq 13 -and $Bytes[$i + 3] -eq 10) {
            return $i
        }
    }
    return -1
}

function Read-HttpRequest($Client) {
    $stream = $Client.GetStream()
    $stream.ReadTimeout = 5000
    $buffer = New-Object byte[] 8192
    $memory = New-Object System.IO.MemoryStream
    $headerEnd = -1

    while ($headerEnd -lt 0) {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { break }
        $memory.Write($buffer, 0, $read)
        $headerEnd = Find-HeaderEnd $memory.ToArray()
    }

    $all = $memory.ToArray()
    if ($headerEnd -lt 0) { throw "Invalid HTTP request" }
    $headerText = [System.Text.Encoding]::UTF8.GetString($all, 0, $headerEnd)
    $first = ($headerText -split "`r?`n")[0] -split " "
    if ($first.Length -lt 2) { throw "Invalid HTTP request line" }

    [pscustomobject]@{
        Method = $first[0].ToUpperInvariant()
        Path = $first[1]
    }
}

function Get-MimeType($Path) {
    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { "text/html; charset=utf-8" }
        ".js" { "text/javascript; charset=utf-8" }
        ".css" { "text/css; charset=utf-8" }
        ".json" { "application/json; charset=utf-8" }
        ".svg" { "image/svg+xml" }
        ".png" { "image/png" }
        ".jpg" { "image/jpeg" }
        ".jpeg" { "image/jpeg" }
        ".ico" { "image/x-icon" }
        default { "application/octet-stream" }
    }
}

function Send-StaticFile($Client, $RequestPath) {
    $pathOnly = ($RequestPath -split "\?")[0]
    $decoded = [System.Uri]::UnescapeDataString($pathOnly).TrimStart("/")
    if ([string]::IsNullOrWhiteSpace($decoded)) { $decoded = "index.html" }
    $relative = $decoded.Replace("/", [System.IO.Path]::DirectorySeparatorChar)
    $full = [System.IO.Path]::GetFullPath((Join-Path $ClientRoot $relative))
    if (-not $full.StartsWith($ClientRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Send-Json $Client 404 @{ error = "not_found" }
        return
    }
    if (-not (Test-Path $full) -or (Get-Item $full).PSIsContainer) {
        $full = Join-Path $ClientRoot "index.html"
    }
    Send-Bytes $Client 200 (Get-MimeType $full) ([System.IO.File]::ReadAllBytes($full))
}

function Get-LocalIPv4 {
    $addresses = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).AddressList |
        Where-Object { $_.AddressFamily -eq "InterNetwork" -and -not $_.IPAddressToString.StartsWith("127.") }
    if ($addresses) { return $addresses[0].IPAddressToString }
    return "127.0.0.1"
}

$listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Any), $Port
$listener.Start()
$ip = Get-LocalIPv4
Write-Host ""
Write-Host "ForHome static test server is running."
Write-Host "PC:     http://localhost:$Port"
Write-Host "Mobile: http://$ip`:$Port"
Write-Host "Mode:   localhost uses local mock storage by default"
Write-Host "Stop:   Ctrl + C"
Write-Host ""
Write-AppLog "static test server started on port $Port"

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $request = Read-HttpRequest $client
        $pathOnly = ($request.Path -split "\?")[0]
        if ($request.Method -eq "OPTIONS") {
            Send-Text $client 204 "text/plain; charset=utf-8" ""
        } elseif ($request.Method -eq "GET" -and $pathOnly -eq "/api/health") {
            Send-Json $client 200 @{ ok = $true; storage = "firebase-firestore"; mode = "static-test"; port = $Port }
        } elseif ($pathOnly.StartsWith("/api/")) {
            Send-Json $client 410 @{ error = "api_removed"; message = "Production storage uses Firebase Firestore." }
        } elseif ($request.Method -eq "GET") {
            Send-StaticFile $client $request.Path
        } else {
            Send-Json $client 405 @{ error = "method_not_allowed" }
        }
    } catch {
        Write-AppLog "request failed: $_"
        try { Send-Json $client 500 @{ error = "server_error"; message = "$_" } } catch {}
    } finally {
        $client.Close()
    }
}
