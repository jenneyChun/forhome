# Sends the ForHome 07:00 morning briefing to each configured Kakao recipient.
param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$envFile = Join-Path $scriptDir "briefing.env.ps1"
$recipientFile = Join-Path $scriptDir "kakao-recipients.json"
$briefingFile = Join-Path $repoRoot "data\exports\morning_briefing.json"
$briefingScript = Join-Path $repoRoot "scripts\firestore-backup.js"

if (Test-Path $envFile) {
    . $envFile
}

function Assert-Node {
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        throw "Node.js was not found. Install Node or run npm install before scheduling the briefing."
    }
    return $node.Source
}

function Read-Recipients {
    if (-not (Test-Path $recipientFile)) {
        throw "Missing server\kakao-recipients.json. Copy server\kakao-recipients.example.json and fill each parent's Kakao tokens."
    }
    $items = Get-Content -Raw -Encoding UTF8 $recipientFile | ConvertFrom-Json
    if (-not $items) { throw "server\kakao-recipients.json has no recipients." }
    return @($items)
}

function New-BriefingFile {
    $node = Assert-Node
    $args = @($briefingScript, "--briefing", "--out-file", $briefingFile)
    if ($env:BRIEFING_DATE) {
        $args += @("--date", $env:BRIEFING_DATE)
    }
    if ($env:FIRESTORE_BRIEFING_FIXTURE) {
        $args += @("--fixture", $env:FIRESTORE_BRIEFING_FIXTURE)
    }
    & $node @args
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build the ForHome briefing."
    }
    return Get-Content -Raw -Encoding UTF8 $briefingFile | ConvertFrom-Json
}

function Update-RecipientRefreshToken($Recipients, $Recipient, $RefreshToken) {
    if (-not $RefreshToken) { return }
    $Recipient.refreshToken = $RefreshToken
    $Recipients | ConvertTo-Json -Depth 20 | Out-File $recipientFile -Encoding utf8
}

function Send-KakaoMemo($Recipient, $Text, $Recipients) {
    $restApiKey = $Recipient.restApiKey
    if (-not $restApiKey) { $restApiKey = $env:KAKAO_REST_API_KEY }
    $refreshToken = $Recipient.refreshToken
    $clientSecret = $Recipient.clientSecret
    if (-not $clientSecret) { $clientSecret = $env:KAKAO_CLIENT_SECRET }
    if (-not $restApiKey -or -not $refreshToken) {
        throw "Recipient $($Recipient.id) must include restApiKey or KAKAO_REST_API_KEY, and refreshToken."
    }

    $tokenBody = @{
        grant_type    = "refresh_token"
        client_id     = $restApiKey
        refresh_token = $refreshToken
    }
    if ($clientSecret) { $tokenBody.client_secret = $clientSecret }

    $tokenResp = Invoke-RestMethod -Uri "https://kauth.kakao.com/oauth/token" -Method Post `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody

    if (-not $tokenResp.access_token) {
        throw "Failed to refresh Kakao access token for $($Recipient.id)."
    }
    Update-RecipientRefreshToken $Recipients $Recipient $tokenResp.refresh_token

    $appUrl = if ($env:FORHOME_APP_URL) { $env:FORHOME_APP_URL } else { "http://localhost:8080" }
    $templateObject = @{
        object_type  = "text"
        text         = $Text
        link         = @{
            web_url        = $appUrl
            mobile_web_url = $appUrl
        }
        button_title = "Open ForHome"
    }
    $template = $templateObject | ConvertTo-Json -Compress -Depth 10
    $encoded = [System.Net.WebUtility]::UrlEncode($template)

    Invoke-RestMethod -Uri "https://kapi.kakao.com/v2/api/talk/memo/default/send" -Method Post `
        -Headers @{ Authorization = "Bearer $($tokenResp.access_token)" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "template_object=$encoded" | Out-Null
}

$recipients = Read-Recipients
$briefing = New-BriefingFile
$text = [string]$briefing.text

if ($DryRun) {
    Write-Host "DRY RUN: briefing would be sent to $(@($recipients).Count) recipients."
    Write-Host $text
    exit 0
}

foreach ($recipient in $recipients) {
    Write-Host "Sending ForHome briefing to $($recipient.id)..."
    Send-KakaoMemo $recipient $text $recipients
}

Write-Host "SUCCESS"
