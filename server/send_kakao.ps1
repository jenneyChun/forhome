# Sends today's ForHome summary to KakaoTalk "memo to me".
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$tokenFile = Join-Path $scriptDir "token.txt"
$summaryFile = Join-Path $repoRoot "data\exports\daily_summary.json"

. (Join-Path $scriptDir "db.ps1")

function Read-TokenFile {
    if (-not (Test-Path $tokenFile)) {
        throw "Missing server\token.txt. Required keys: KAKAO_REST_API_KEY, KAKAO_REFRESH_TOKEN, optional KAKAO_CLIENT_SECRET."
    }
    $tokens = @{}
    Get-Content $tokenFile -Encoding UTF8 | ForEach-Object {
        if ($_ -match "^(\w+)\s*=\s*(.+)$") {
            $tokens[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $tokens
}

function Get-TodayStartMs {
    $epoch = [DateTime]::SpecifyKind([DateTime]"1970-01-01T00:00:00", [DateTimeKind]::Utc)
    return [int64](([DateTime]::Today.ToUniversalTime() - $epoch).TotalMilliseconds)
}

function ConvertFrom-JsTime($milliseconds) {
    $epoch = [DateTime]::SpecifyKind([DateTime]"1970-01-01T00:00:00", [DateTimeKind]::Utc)
    return $epoch.AddMilliseconds([double]$milliseconds).ToLocalTime()
}

function New-SummaryFromPostgres {
    Initialize-Database
    $state = Get-DbState
    $todayStart = Get-TodayStartMs
    $members = @{}
    foreach ($m in @($state.members)) { $members[$m.id] = $m }
    $chores = @{}
    foreach ($c in @($state.chores)) { $chores[$c.id] = $c }

    $tasks = @($state.history | Where-Object { [int64]$_.timestamp -ge $todayStart } | ForEach-Object {
        $m = $members[$_.memberId]
        $c = $chores[$_.choreId]
        [pscustomobject]@{
            memberName  = if ($m) { $m.name } else { $_.memberId }
            memberEmoji = if ($m) { $m.emoji } else { "user" }
            choreName   = if ($_.choreName) { $_.choreName } elseif ($c) { $c.name } else { "task" }
            choreEmoji  = if ($_.choreEmoji) { $_.choreEmoji } elseif ($c) { $c.emoji } else { "ok" }
            xp          = if ($_.xpEarned) { $_.xpEarned } else { 0 }
            time        = (ConvertFrom-JsTime $_.timestamp).ToString("HH:mm")
        }
    })

    $messages = @($state.messages | Where-Object { [int64]$_.timestamp -ge $todayStart } | ForEach-Object {
        $from = $members[$_.fromId]
        $to = if ($_.toId) { $members[$_.toId] } else { $null }
        [pscustomobject]@{
            from      = if ($from) { $from.name } else { $_.fromId }
            fromEmoji = if ($from) { $from.emoji } else { "admin" }
            to        = if ($to) { $to.name } else { "all" }
            text      = $_.text
            time      = (ConvertFrom-JsTime $_.timestamp).ToString("HH:mm")
        }
    })

    [pscustomobject]@{
        date     = (Get-Date).ToString("yyyy-MM-dd")
        tasks    = $tasks
        messages = $messages
    }
}

function Build-KakaoText($summary) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("ForHome daily summary")
    $lines.Add("Date: $($summary.date)")
    $lines.Add("")

    if (@($summary.tasks).Count -gt 0) {
        $lines.Add("Tasks ($(@($summary.tasks).Count))")
        @($summary.tasks) | Group-Object memberName | ForEach-Object {
            $first = $_.Group[0]
            $chores = ($_.Group | ForEach-Object { "$($_.choreEmoji) $($_.choreName)" }) -join " / "
            $lines.Add("$($first.memberEmoji) $($_.Name): $chores")
        }
    } else {
        $lines.Add("No completed tasks today.")
    }

    $lines.Add("")
    if (@($summary.messages).Count -gt 0) {
        $lines.Add("Messages ($(@($summary.messages).Count))")
        @($summary.messages) | ForEach-Object {
            $line = "$($_.fromEmoji) $($_.from) -> $($_.to): $($_.text)"
            if ($line.Length -gt 70) { $line = $line.Substring(0, 67) + "..." }
            $lines.Add($line)
        }
    } else {
        $lines.Add("No family messages today.")
    }

    $text = $lines -join "`n"
    if ($text.Length -gt 1800) { $text = $text.Substring(0, 1797) + "..." }
    return $text
}

$tokens = Read-TokenFile
$restApiKey = $tokens["KAKAO_REST_API_KEY"]
$clientSecret = $tokens["KAKAO_CLIENT_SECRET"]
$refreshToken = $tokens["KAKAO_REFRESH_TOKEN"]

if (-not $restApiKey -or -not $refreshToken) {
    throw "server\token.txt must include KAKAO_REST_API_KEY and KAKAO_REFRESH_TOKEN."
}

Write-Host "Refreshing Kakao access token..."
$tokenBody = @{
    grant_type    = "refresh_token"
    client_id     = $restApiKey
    refresh_token = $refreshToken
}
if ($clientSecret) { $tokenBody.client_secret = $clientSecret }

$tokenResp = Invoke-RestMethod -Uri "https://kauth.kakao.com/oauth/token" -Method Post `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $tokenBody

$accessToken = $tokenResp.access_token
if (-not $accessToken) { throw "Failed to refresh Kakao access token." }

if ($tokenResp.refresh_token) {
    $content = Get-Content $tokenFile -Encoding UTF8
    $content = $content -replace "KAKAO_REFRESH_TOKEN\s*=\s*.+", "KAKAO_REFRESH_TOKEN = $($tokenResp.refresh_token)"
    $content | Out-File $tokenFile -Encoding utf8
    Write-Host "Refresh token was updated."
}

$summary = New-SummaryFromPostgres
$summaryDir = Split-Path -Parent $summaryFile
if (-not (Test-Path $summaryDir)) { New-Item -ItemType Directory -Force -Path $summaryDir | Out-Null }
$summary | ConvertTo-Json -Depth 20 | Out-File $summaryFile -Encoding utf8
$msgText = Build-KakaoText $summary

Write-Host "Sending Kakao memo..."
$templateObject = @{
    object_type  = "text"
    text         = $msgText
    link         = @{
        web_url        = "http://localhost:8080"
        mobile_web_url = "http://localhost:8080"
    }
    button_title = "Open"
}
$template = $templateObject | ConvertTo-Json -Compress -Depth 10
$encoded = [System.Net.WebUtility]::UrlEncode($template)

Invoke-RestMethod -Uri "https://kapi.kakao.com/v2/api/talk/memo/default/send" -Method Post `
    -Headers @{ Authorization = "Bearer $accessToken" } `
    -ContentType "application/x-www-form-urlencoded" `
    -Body "template_object=$encoded" | Out-Null

Write-Host "SUCCESS"
Write-Host $msgText
