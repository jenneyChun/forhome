param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
$ClientRoot = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "code"))
$LogDir = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot "log"))

. (Join-Path $ScriptDir "db.ps1")

function Write-AppLog($Message) {
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
    }
    Add-Content -Path (Join-Path $LogDir "server.log") -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

function Get-ReasonPhrase($Status) {
    switch ($Status) {
        200 { "OK" }
        201 { "Created" }
        204 { "No Content" }
        400 { "Bad Request" }
        401 { "Unauthorized" }
        403 { "Forbidden" }
        404 { "Not Found" }
        405 { "Method Not Allowed" }
        500 { "Internal Server Error" }
        default { "OK" }
    }
}

function New-HeaderText($Status, $ContentType, $Length, $ExtraHeaders) {
    $reason = Get-ReasonPhrase $Status
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("HTTP/1.1 $Status $reason")
    if ($ContentType) { $lines.Add("Content-Type: $ContentType") }
    $lines.Add("Content-Length: $Length")
    $origin = "http://localhost:$Port"
    if ($script:RequestOrigin -and $script:AllowedOrigins -contains $script:RequestOrigin) {
        $origin = $script:RequestOrigin
    }
    $lines.Add("Access-Control-Allow-Origin: $origin")
    $lines.Add("Access-Control-Allow-Credentials: true")
    $lines.Add("Access-Control-Allow-Headers: Content-Type")
    $lines.Add("Access-Control-Allow-Methods: GET, POST, PUT, OPTIONS")
    $lines.Add("Cache-Control: no-store")
    $lines.Add("Connection: close")
    if ($ExtraHeaders) {
        foreach ($key in $ExtraHeaders.Keys) {
            $value = $ExtraHeaders[$key]
            if ($value -is [array]) {
                foreach ($item in $value) { $lines.Add("$key`: $item") }
            } else {
                $lines.Add("$key`: $value")
            }
        }
    }
    return (($lines -join "`r`n") + "`r`n`r`n")
}

function Send-Bytes($Client, $Status, $ContentType, [byte[]]$Bytes, $ExtraHeaders = $null) {
    $stream = $Client.GetStream()
    $headers = New-HeaderText $Status $ContentType $Bytes.Length $ExtraHeaders
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($Bytes.Length -gt 0) {
        $stream.Write($Bytes, 0, $Bytes.Length)
    }
}

function Send-Text($Client, $Status, $ContentType, $Text, $ExtraHeaders = $null) {
    if ($null -eq $Text) { $Text = "" }
    Send-Bytes $Client $Status $ContentType ([System.Text.Encoding]::UTF8.GetBytes($Text)) $ExtraHeaders
}

function Send-Json($Client, $Status, $Object, $ExtraHeaders = $null) {
    Send-Text $Client $Status "application/json; charset=utf-8" ($Object | ConvertTo-Json -Depth 40) $ExtraHeaders
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

function Convert-Headers($HeaderText) {
    $headers = @{}
    $lines = $HeaderText -split "`r?`n"
    for ($i = 1; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        $idx = $line.IndexOf(":")
        if ($idx -lt 1) { continue }
        $name = $line.Substring(0, $idx).Trim().ToLowerInvariant()
        $value = $line.Substring($idx + 1).Trim()
        $headers[$name] = $value
    }
    return $headers
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

    $headers = Convert-Headers $headerText
    $contentLength = 0
    if ($headers.ContainsKey("content-length")) {
        $contentLength = [int]$headers["content-length"]
    }
    $bodyStart = $headerEnd + 4
    $alreadyRead = $all.Length - $bodyStart
    while ($alreadyRead -lt $contentLength) {
        $read = $stream.Read($buffer, 0, [Math]::Min($buffer.Length, $contentLength - $alreadyRead))
        if ($read -le 0) { break }
        $memory.Write($buffer, 0, $read)
        $alreadyRead += $read
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
        BodyText = $body
    }
}

function Read-JsonBody($Request) {
    if ([string]::IsNullOrWhiteSpace($Request.BodyText)) { return [pscustomobject]@{} }
    try {
        return ($Request.BodyText | ConvertFrom-Json)
    } catch {
        throw "JSON body is invalid."
    }
}

function Get-CookieValue($Headers, $Name) {
    if (-not $Headers.ContainsKey("cookie")) { return $null }
    $cookies = $Headers["cookie"] -split ";"
    foreach ($cookie in $cookies) {
        $parts = $cookie.Trim() -split "=", 2
        if ($parts.Length -eq 2 -and $parts[0] -eq $Name) {
            return [System.Uri]::UnescapeDataString($parts[1])
        }
    }
    return $null
}

function New-SessionCookie($Token) {
    return "$SessionCookieName=$([System.Uri]::EscapeDataString($Token)); Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"
}

function New-ExpiredSessionCookie {
    return "$SessionCookieName=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
}

function Get-RequestSession($Request) {
    $token = Get-CookieValue $Request.Headers $SessionCookieName
    if (-not $token) { return $null }
    return Get-DbSession $token
}

function Require-Session($Request) {
    $session = Get-RequestSession $Request
    if (-not $session) { throw "Login is required." }
    return $session
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
    if ($decoded.StartsWith("invite/")) { $decoded = "index.html" }
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

function Send-ApiError($Client, $Status, $Code, $Message) {
    Send-Json $Client $Status @{ ok = $false; error = $Code; message = $Message }
}

function Handle-ApiRequest($Client, $Request, $PathOnly) {
    if ($Request.Method -eq "OPTIONS") {
        Send-Text $Client 204 "text/plain; charset=utf-8" ""
        return
    }

    if ($Request.Method -eq "GET" -and $PathOnly -eq "/api/health") {
        $health = Get-DbHealth
        $health | Add-Member -NotePropertyName port -NotePropertyValue $Port -Force
        Send-Json $Client 200 $health
        return
    }

    if ($Request.Method -eq "POST" -and $PathOnly -eq "/api/auth/register-owner") {
        $body = Read-JsonBody $Request
        $result = Register-Owner $body
        Send-Json $Client 201 @{ ok = $true; session = $result.session } @{ "Set-Cookie" = (New-SessionCookie $result.token) }
        return
    }

    if ($Request.Method -eq "POST" -and $PathOnly -eq "/api/auth/login") {
        $body = Read-JsonBody $Request
        $accountId = if ($body.accountId) { $body.accountId } else { $body.id }
        $result = Login-DbUser $accountId $body.password
        Send-Json $Client 200 @{ ok = $true; session = $result.session } @{ "Set-Cookie" = (New-SessionCookie $result.token) }
        return
    }

    if ($Request.Method -eq "POST" -and $PathOnly -eq "/api/auth/logout") {
        $token = Get-CookieValue $Request.Headers $SessionCookieName
        Clear-DbSession $token
        Send-Json $Client 200 @{ ok = $true } @{ "Set-Cookie" = (New-ExpiredSessionCookie) }
        return
    }

    if ($Request.Method -eq "GET" -and $PathOnly -eq "/api/session") {
        $session = Get-RequestSession $Request
        if ($session) {
            Send-Json $Client 200 @{ authenticated = $true; session = $session }
        } else {
            Send-Json $Client 200 @{ authenticated = $false; session = $null }
        }
        return
    }

    if ($Request.Method -eq "GET" -and $PathOnly -eq "/api/state") {
        $session = Require-Session $Request
        Send-Json $Client 200 (Get-DbState $session.householdId)
        return
    }

    if (($Request.Method -eq "PUT" -or $Request.Method -eq "POST") -and $PathOnly -eq "/api/state") {
        $session = Require-Session $Request
        $body = Read-JsonBody $Request
        Send-Json $Client 200 (Set-DbState $body $session.householdId)
        return
    }

    if ($Request.Method -eq "POST" -and $PathOnly -eq "/api/invites") {
        $session = Require-Session $Request
        $body = Read-JsonBody $Request
        Send-Json $Client 201 @{ ok = $true; invitation = (New-DbInvitation $session $body) }
        return
    }

    if ($PathOnly -match "^/api/invites/([^/]+)$") {
        $inviteId = [System.Uri]::UnescapeDataString($matches[1])
        if ($Request.Method -eq "GET") {
            Send-Json $Client 200 @{ ok = $true; invitation = (Get-DbInvitationPreview $inviteId) }
            return
        }
        if ($Request.Method -eq "POST") {
            $body = Read-JsonBody $Request
            $result = Accept-DbInvitation $inviteId $body
            Send-Json $Client 200 @{ ok = $true; session = $result.session } @{ "Set-Cookie" = (New-SessionCookie $result.token) }
            return
        }
    }

    Send-ApiError $Client 404 "not_found" "API route not found."
}

function Get-LocalIPv4 {
    $addresses = [System.Net.Dns]::GetHostEntry([System.Net.Dns]::GetHostName()).AddressList |
        Where-Object { $_.AddressFamily -eq "InterNetwork" -and -not $_.IPAddressToString.StartsWith("127.") }
    if ($addresses) { return $addresses[0].IPAddressToString }
    return "127.0.0.1"
}

function Stop-ProcessTree {
    param([int]$ProcessId)

    if (-not $ProcessId -or $ProcessId -eq $PID) { return }
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue |
        ForEach-Object { Stop-ProcessTree -ProcessId $_.ProcessId }
    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    cmd /c "taskkill /PID $ProcessId /F /T >nul 2>nul"
}

function Stop-PortOwner {
    param([int]$OwnerPid)

    if (-not $OwnerPid -or $OwnerPid -eq $PID) { return }
    $proc = Get-Process -Id $OwnerPid -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Stopping $($proc.ProcessName) (PID $OwnerPid)..."
        Write-AppLog "stopping process $OwnerPid ($($proc.ProcessName))"
        Stop-ProcessTree -ProcessId $OwnerPid
        return
    }

    Write-Host "Port owner PID $OwnerPid not found; stopping child processes..."
    Write-AppLog "port owner pid $OwnerPid not found; stopping children"
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$OwnerPid" -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Host "  stopping child $($_.ProcessId) $($_.Name)"
            Write-AppLog "stopping child $($_.ProcessId) $($_.Name) of ghost pid $OwnerPid"
            Stop-ProcessTree -ProcessId $_.ProcessId
        }
    cmd /c "taskkill /PID $OwnerPid /F /T >nul 2>nul"
}

function Clear-PortListener {
    param([int]$Port)

    $currentPid = $PID
    $protected = New-Object 'System.Collections.Generic.HashSet[int]'
    $protected.Add($currentPid) | Out-Null
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$currentPid" -ErrorAction SilentlyContinue
    while ($proc -and $proc.ParentProcessId) {
        $protected.Add($proc.ParentProcessId) | Out-Null
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($proc.ParentProcessId)" -ErrorAction SilentlyContinue
    }

    for ($attempt = 1; $attempt -le 6; $attempt++) {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                -not $protected.Contains($_.ProcessId) -and
                $_.CommandLine -match 'server\.ps1' -and
                $_.CommandLine -match "-Port\s+$Port\b"
            } |
            ForEach-Object {
                Write-Host "Stopping leftover server process (PID $($_.ProcessId))..."
                Write-AppLog "stopping leftover server process $($_.ProcessId)"
                Stop-ProcessTree -ProcessId $_.ProcessId
            }

        $relatedPids = @(Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -eq $Port -and $_.State -eq "Listen" } |
            Select-Object -ExpandProperty OwningProcess -Unique |
            Where-Object { $_ -and -not $protected.Contains($_) })
        foreach ($ownerPid in $relatedPids) {
            Stop-PortOwner -OwnerPid $ownerPid
        }

        Start-Sleep -Milliseconds (250 * $attempt)
        if (-not (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)) {
            return
        }
    }
}

function Start-ServerListeners {
    param([int]$Port, [string]$LanIP)

    Clear-PortListener -Port $Port

    $listeners = New-Object System.Collections.Generic.List[System.Net.Sockets.TcpListener]
    try {
        $anyListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Any), $Port
        $anyListener.Start()
        $listeners.Add($anyListener) | Out-Null
        Write-AppLog "listening on 0.0.0.0:$Port"
        return $listeners
    } catch {
        Write-Host "Could not bind 0.0.0.0:$Port ($($_.Exception.Message)); trying per-interface bind..."
        Write-AppLog "bind 0.0.0.0:$Port failed: $_"
    }

    foreach ($addrText in @($LanIP, "127.0.0.1")) {
        if ($listeners | Where-Object {
            $ep = $_.LocalEndpoint
            $ep.Address.ToString() -eq $addrText -and $ep.Port -eq $Port
        }) { continue }
        try {
            $ipAddress = [System.Net.IPAddress]::Parse($addrText)
            $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList $ipAddress, $Port
            $listener.Start()
            $listeners.Add($listener) | Out-Null
            Write-Host "Listening on http://${addrText}:$Port"
            Write-AppLog "listening on ${addrText}:$Port"
        } catch {
            Write-Host "Could not bind ${addrText}:$Port ($($_.Exception.Message))"
            Write-AppLog "bind ${addrText}:$Port failed: $_"
        }
    }

    if ($listeners.Count -eq 0) {
        throw "Port $Port is still in use. Close the process holding it or reboot to clear a stale listener."
    }
    return $listeners
}

$ip = Get-LocalIPv4
$script:AllowedOrigins = @(
    "http://localhost:$Port",
    "http://127.0.0.1:$Port",
    "http://${ip}:$Port"
)
$listeners = Start-ServerListeners -Port $Port -LanIP $ip
Write-Host ""
Write-Host "ForHome PostgreSQL API server is running."
Write-Host "PC:     http://localhost:$Port"
Write-Host "LAN:    http://$ip`:$Port"
Write-Host "DB:     PGHOST/PGPORT/PGDATABASE/PGUSER/PGPASSWORD or data\db.env.ps1"
Write-Host "Stop:   Ctrl + C"
Write-Host ""
Write-AppLog "postgresql api server started on port $Port (listeners=$($listeners.Count))"

try {
while ($true) {
    $client = $null
    while (-not $client) {
        foreach ($listener in $listeners) {
            if ($listener.Pending()) {
                $client = $listener.AcceptTcpClient()
                break
            }
        }
        if (-not $client) { Start-Sleep -Milliseconds 25 }
    }
    try {
        $request = Read-HttpRequest $client
        $script:RequestOrigin = $null
        if ($request.Headers.ContainsKey("origin")) {
            $script:RequestOrigin = $request.Headers["origin"]
        }
        $pathOnly = ($request.Path -split "\?")[0]
        if ($pathOnly.StartsWith("/api/")) {
            try {
                Handle-ApiRequest $client $request $pathOnly
            } catch {
                $status = 500
                $code = "server_error"
                $message = "$_"
                if ($message -match "Login is required") {
                    $status = 401
                    $code = "unauthorized"
                } elseif ($message -match "permission") {
                    $status = 403
                    $code = "forbidden"
                } elseif ($message -match "(?<!was )not found(?!\. Install PostgreSQL)") {
                    $status = 404
                    $code = "not_found"
                } elseif ($message -match "password authentication failed|no password supplied|Cannot connect to PostgreSQL|psql was not found") {
                    $status = 503
                    $code = "database_unavailable"
                } elseif ($message -match "password|JSON body|required|invalid|expired|used|revoked") {
                    $status = 400
                    $code = "bad_request"
                }
                Send-ApiError $client $status $code $message
            }
        } elseif ($request.Method -eq "GET") {
            Send-StaticFile $client $request.Path
        } elseif ($request.Method -eq "OPTIONS") {
            Send-Text $client 204 "text/plain; charset=utf-8" ""
        } else {
            Send-ApiError $client 405 "method_not_allowed" "Method not allowed."
        }
    } catch {
        Write-AppLog "request failed: $_"
        try { Send-ApiError $client 500 "server_error" "$_" } catch {}
    } finally {
        $client.Close()
    }
}
} finally {
    foreach ($listener in $listeners) {
        try { $listener.Stop() } catch {}
    }
    Write-AppLog "server stopped on port $Port"
}
