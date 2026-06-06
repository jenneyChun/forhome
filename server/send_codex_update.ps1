# Sends a ForHome Codex/GitHub update to configured Kakao recipients.
param(
    [string]$Summary,
    [string]$CommitSha,
    [string]$CommitUrl,
    [string]$Repository,
    [string]$Actor,
    [string]$RunUrl,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$envFile = Join-Path $scriptDir "briefing.env.ps1"
$recipientFile = Join-Path $scriptDir "kakao-recipients.json"

if (Test-Path $envFile) {
    . $envFile
}

function Invoke-Git {
    param([string[]]$GitArgs)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return "" }

    Push-Location $repoRoot
    try {
        $fullArgs = @("-c", "core.excludesfile=") + $GitArgs
        $oldErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & $git.Source @fullArgs 2>$null
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldErrorActionPreference
        if ($exitCode -ne 0) { return "" }
        return (($output | Out-String).Trim())
    } finally {
        Pop-Location
    }
}

function Get-GitHubRepoUrl {
    $remote = Invoke-Git @("remote", "get-url", "origin")
    if (-not $remote) { return "" }

    if ($remote -match "^git@github\.com:(.+)$") {
        $path = $Matches[1] -replace "\.git$", ""
        return "https://github.com/$path"
    }

    if ($remote -match "^https://github\.com/(.+)$") {
        $path = $Matches[1] -replace "\.git$", ""
        return "https://github.com/$path"
    }

    return ""
}

function Read-Recipients {
    if ($env:KAKAO_RECIPIENTS_JSON) {
        $items = $env:KAKAO_RECIPIENTS_JSON | ConvertFrom-Json
        return [pscustomobject]@{ Source = "env"; Items = @($items) }
    }

    if (-not (Test-Path $recipientFile)) {
        throw "Missing server\kakao-recipients.json or KAKAO_RECIPIENTS_JSON."
    }

    $items = Get-Content -Raw -Encoding UTF8 $recipientFile | ConvertFrom-Json
    return [pscustomobject]@{ Source = "file"; Items = @($items) }
}

function Update-RecipientRefreshToken {
    param($RecipientData, $Recipient, [string]$RefreshToken)

    if (-not $RefreshToken) { return }

    if ($Recipient.PSObject.Properties.Name -contains "refreshToken") {
        $Recipient.refreshToken = $RefreshToken
    } else {
        $Recipient | Add-Member -NotePropertyName "refreshToken" -NotePropertyValue $RefreshToken
    }

    if ($RecipientData.Source -eq "file") {
        $RecipientData.Items | ConvertTo-Json -Depth 20 | Out-File $recipientFile -Encoding utf8
    } else {
        Write-Warning "Kakao issued a new refresh token for $($Recipient.id). Update the KAKAO_RECIPIENTS_JSON secret soon."
    }
}

function Send-KakaoMemo {
    param($RecipientData, $Recipient, [string]$Text, [string]$LinkUrl)

    $restApiKey = $Recipient.restApiKey
    if (-not $restApiKey) { $restApiKey = $env:KAKAO_REST_API_KEY }

    $clientSecret = $Recipient.clientSecret
    if (-not $clientSecret) { $clientSecret = $env:KAKAO_CLIENT_SECRET }

    $refreshToken = $Recipient.refreshToken
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
    Update-RecipientRefreshToken $RecipientData $Recipient $tokenResp.refresh_token

    $templateObject = @{
        object_type  = "text"
        text         = $Text
        link         = @{
            web_url        = $LinkUrl
            mobile_web_url = $LinkUrl
        }
        button_title = "Open GitHub"
    }
    $template = $templateObject | ConvertTo-Json -Compress -Depth 10
    $encoded = [System.Net.WebUtility]::UrlEncode($template)

    Invoke-RestMethod -Uri "https://kapi.kakao.com/v2/api/talk/memo/default/send" -Method Post `
        -Headers @{ Authorization = "Bearer $($tokenResp.access_token)" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "template_object=$encoded" | Out-Null
}

if (-not $CommitSha) { $CommitSha = Invoke-Git @("rev-parse", "HEAD") }
if (-not $Summary) { $Summary = Invoke-Git @("log", "-1", "--pretty=%s") }
if (-not $Repository) {
    if ($env:GITHUB_REPOSITORY) { $Repository = $env:GITHUB_REPOSITORY }
}

$repoUrl = Get-GitHubRepoUrl
if (-not $CommitUrl -and $env:GITHUB_SERVER_URL -and $env:GITHUB_REPOSITORY -and $CommitSha) {
    $CommitUrl = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/commit/$CommitSha"
}
if (-not $CommitUrl -and $repoUrl -and $CommitSha) {
    $CommitUrl = "$repoUrl/commit/$CommitSha"
}
if (-not $RunUrl -and $env:GITHUB_RUN_URL) { $RunUrl = $env:GITHUB_RUN_URL }
if (-not $Actor -and $env:GITHUB_ACTOR) { $Actor = $env:GITHUB_ACTOR }

$shortSha = $CommitSha
if ($shortSha -and $shortSha.Length -gt 7) { $shortSha = $shortSha.Substring(0, 7) }

$dirtyStatus = Invoke-Git @("status", "--short", "--untracked-files=no")
$worktreeLine = "Working tree: clean"
if ($dirtyStatus) { $worktreeLine = "Working tree: has local changes" }

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("ForHome Codex update")
$lines.Add("GitHub reflected implementation is ready.")
if ($Repository) { $lines.Add("Repository: $Repository") }
if ($shortSha) { $lines.Add("Commit: $shortSha") }
if ($Summary) { $lines.Add("Message: $Summary") }
if ($CommitUrl) { $lines.Add("GitHub: $CommitUrl") }
if ($RunUrl) { $lines.Add("Action: $RunUrl") }
if ($Actor) { $lines.Add("Actor: $Actor") }
$lines.Add($worktreeLine)
$lines.Add("")
$lines.Add("Codex follow-up commands")
$lines.Add("Codex implement: <request>")
$lines.Add("Codex verify: npm run test:e2e")
$lines.Add("Codex deploy: firebase deploy --only firestore:rules,hosting")
$lines.Add("")
$lines.Add("Note: Kakao message replies are not auto-read until a Kakao Channel webhook bridge is connected.")

$text = $lines -join "`n"
if ($text.Length -gt 1800) { $text = $text.Substring(0, 1797) + "..." }

$linkUrl = $CommitUrl
if (-not $linkUrl) { $linkUrl = $repoUrl }
if (-not $linkUrl) { $linkUrl = $env:FORHOME_APP_URL }
if (-not $linkUrl) { $linkUrl = "https://github.com" }

if ($DryRun) {
    Write-Host "DRY RUN: Codex update notification would be sent."
    Write-Host $text
    exit 0
}

$recipientData = Read-Recipients
if (-not $recipientData.Items -or @($recipientData.Items).Count -eq 0) {
    throw "No Kakao recipients configured."
}

foreach ($recipient in @($recipientData.Items)) {
    Write-Host "Sending Codex update to $($recipient.id)..."
    Send-KakaoMemo $recipientData $recipient $text $linkUrl
}

Write-Host "SUCCESS"
