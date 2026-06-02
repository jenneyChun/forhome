param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
$ClientRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "code"))
$ExportDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "data\exports"))
$LogDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "log"))
$SummaryPath = Join-Path $ExportDir "daily_summary.json"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

. (Join-Path $ScriptDir "db.ps1")

function Write-Utf8File($Path, $Text) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Write-AppLog($Message) {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    $line = "$(Get-Date -Format o) $Message"
    Add-Content -Path (Join-Path $LogDir "server.log") -Value $line -Encoding UTF8
}

function Get-ReasonPhrase($Status) {
    switch ($Status) {
        200 { "OK" }
        201 { "Created" }
        204 { "No Content" }
        400 { "Bad Request" }
        404 { "Not Found" }
        405 { "Method Not Allowed" }
        500 { "Internal Server Error" }
        default { "OK" }
    }
}

function Send-Bytes($Client, $Status, $ContentType, [byte[]]$Bytes) {
    $stream = $Client.GetStream()
    $reason = Get-ReasonPhrase $Status
    $headers = "HTTP/1.1 $Status $reason`r`nContent-Type: $ContentType`r`nContent-Length: $($Bytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nAccess-Control-Allow-Headers: Content-Type`r`nAccess-Control-Allow-Methods: GET, POST, OPTIONS`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
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
    $json = $Object
    if ($Object -isnot [string]) {
        $json = $Object | ConvertTo-Json -Depth 60
    }
    Send-Text $Client $Status "application/json; charset=utf-8" $json
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
    if ($headerEnd -lt 0) {
        throw "Invalid HTTP request"
    }

    $headerText = [System.Text.Encoding]::UTF8.GetString($all, 0, $headerEnd)
    $lines = $headerText -split "`r?`n"
    $first = $lines[0] -split " "
    if ($first.Length -lt 2) {
        throw "Invalid HTTP request line"
    }

    $headers = @{}
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $idx = $line.IndexOf(":")
        if ($idx -gt 0) {
            $headers[$line.Substring(0, $idx).Trim().ToLowerInvariant()] = $line.Substring($idx + 1).Trim()
        }
    }

    $bodyStart = $headerEnd + 4
    $contentLength = 0
    if ($headers.ContainsKey("content-length")) {
        $contentLength = [int]$headers["content-length"]
    }
    while (($memory.Length - $bodyStart) -lt $contentLength) {
        $read = $stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) { break }
        $memory.Write($buffer, 0, $read)
    }

    $all = $memory.ToArray()
    $body = ""
    if ($contentLength -gt 0) {
        $body = [System.Text.Encoding]::UTF8.GetString($all, $bodyStart, $contentLength)
    }

    [pscustomobject]@{
        Method = $first[0].ToUpperInvariant()
        Path = $first[1]
        Headers = $headers
        Body = $body
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
        Send-Json $Client 404 @{ error = "not_found" }
        return
    }
    Send-Bytes $Client 200 (Get-MimeType $full) ([System.IO.File]::ReadAllBytes($full))
}

function Handle-Api($Client, $Request) {
    if ($Request.Method -eq "OPTIONS") {
        Send-Text $Client 204 "text/plain; charset=utf-8" ""
        return
    }

    $pathOnly = ($Request.Path -split "\?")[0]
    if ($Request.Method -eq "GET" -and $pathOnly -eq "/api/health") {
        Send-Json $Client 200 @{ ok = $true; storage = "postgresql"; time = [DateTime]::Now.ToString("o"); port = $Port }
        return
    }
    if ($Request.Method -eq "GET" -and $pathOnly -eq "/api/state") {
        Send-Json $Client 200 (Get-DbState)
        return
    }
    if ($Request.Method -eq "POST" -and $pathOnly -eq "/api/state") {
        try {
            Send-Json $Client 200 (Set-DbState $Request.Body)
        } catch {
            Write-AppLog "state save failed: $_"
            Send-Json $Client 400 @{ error = "invalid_state"; message = "$_" }
        }
        return
    }
    if ($Request.Method -eq "POST" -and $pathOnly -eq "/api/daily-summary") {
        try {
            $Request.Body | ConvertFrom-Json | Out-Null
            Write-Utf8File $SummaryPath $Request.Body
            Send-Json $Client 200 @{ ok = $true; path = $SummaryPath }
        } catch {
            Send-Json $Client 400 @{ error = "invalid_summary"; message = "$_" }
        }
        return
    }
    Send-Json $Client 404 @{ error = "not_found" }
}

function Get-LocalIPv4 {
    $addresses = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).AddressList |
        Where-Object { $_.AddressFamily -eq "InterNetwork" -and -not $_.IPAddressToString.StartsWith("127.") }
    if ($addresses) { return $addresses[0].IPAddressToString }
    return "127.0.0.1"
}

Initialize-Database
$listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Any), $Port
$listener.Start()
$ip = Get-LocalIPv4
Write-Host ""
Write-Host "ForHome server is running with PostgreSQL."
Write-Host "PC:     http://localhost:$Port"
Write-Host "Mobile: http://$ip`:$Port"
Write-Host "Stop:   Ctrl + C"
Write-Host ""
Write-AppLog "server started on port $Port"

while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
        $request = Read-HttpRequest $client
        if (($request.Path -split "\?")[0].StartsWith("/api/")) {
            Handle-Api $client $request
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
