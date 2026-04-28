# send_kakao.ps1
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 1. token.txt
$tokenFile = Join-Path $scriptDir "token.txt"
$tokens = @{}
Get-Content $tokenFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^(\w+)\s*=\s*(.+)$") { $tokens[$Matches[1]] = $Matches[2].Trim() }
}
$restApiKey   = $tokens["KAKAO_REST_API_KEY"]
$clientSecret = $tokens["KAKAO_CLIENT_SECRET"]
$refreshToken = $tokens["KAKAO_REFRESH_TOKEN"]

# 2. Access Token
Write-Host "Access Token ..."
try {
    $tokenResp = Invoke-RestMethod -Uri "https://kauth.kakao.com/oauth/token" -Method Post `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "grant_type=refresh_token&client_id=$restApiKey&refresh_token=$refreshToken&client_secret=$clientSecret"
} catch {
    Write-Host "Token Error: $_"; exit 1
}
$accessToken = $tokenResp.access_token
if ($tokenResp.refresh_token) {
    $c = Get-Content $tokenFile -Encoding UTF8
    $c = $c -replace "KAKAO_REFRESH_TOKEN = .+", "KAKAO_REFRESH_TOKEN = $($tokenResp.refresh_token)"
    $c | Out-File $tokenFile -Encoding utf8
    Write-Host "Refresh Token updated"
}

# 3. daily_summary.json
$localPath     = Join-Path $scriptDir "daily_summary.json"
$downloadsPath = Join-Path $env:USERPROFILE "Downloads\daily_summary.json"
if (Test-Path $localPath) { $summaryPath = $localPath }
elseif (Test-Path $downloadsPath) { $summaryPath = $downloadsPath; Copy-Item $downloadsPath $localPath }
else { Write-Host "daily_summary.json not found"; exit 1 }

$summary  = Get-Content $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$date     = $summary.date
$tasks    = $summary.tasks
$messages = $summary.messages

# 4. Message
$header = [char]0xD83C + [char]0xDFE0  # house emoji workaround
$nl = "`n"

$taskLabel = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes("✅ 오늘 집안일"))
$msgLabel  = [System.Text.Encoding]::UTF8.GetString([System.Text.Encoding]::UTF8.GetBytes("💬 가족 메시지"))

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add("🏠 우리 집 히어로 일일 요약")
$lines.Add("📅 $date")
$lines.Add("")

if ($tasks.Count -gt 0) {
    $lines.Add("✅ 오늘 집안일 ($($tasks.Count)건)")
    $tasks | Group-Object memberName | ForEach-Object {
        $chores = ($_.Group | ForEach-Object { "$($_.choreEmoji)$($_.choreName)" }) -join " · "
        $lines.Add("$($_.Group[0].memberEmoji) $($_.Name): $chores")
    }
} else { $lines.Add("✅ 오늘 완료한 집안일이 없어요") }

$lines.Add("")
if ($messages.Count -gt 0) {
    $lines.Add("💬 가족 메시지 ($($messages.Count)건)")
    $messages | ForEach-Object {
        $line = "$($_.fromEmoji) $($_.from) -> $($_.to): $($_.text)"
        if ($line.Length -gt 45) { $line = $line.Substring(0,42)+"..." }
        $lines.Add($line)
    }
} else { $lines.Add("💬 가족 메시지가 없어요") }

$msgText = $lines -join "`n"
if ($msgText.Length -gt 200) { $msgText = $msgText.Substring(0,197)+"..." }

# 5. Send
Write-Host "Sending KakaoTalk..."
$template = '{"object_type":"text","text":' + (ConvertTo-Json $msgText -Compress) + ',"link":{"web_url":"https://cejingme.github.io/forhome","mobile_web_url":"https://cejingme.github.io/forhome"}}'
$encoded  = [System.Net.WebUtility]::UrlEncode($template)

try {
    $r = Invoke-RestMethod -Uri "https://kapi.kakao.com/v2/api/talk/memo/default/send" -Method Post `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "template_object=$encoded"
    Write-Host "SUCCESS!"
    Write-Host $msgText
} catch {
    Write-Host "FAILED: $_"; exit 1
}
