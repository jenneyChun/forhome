# =====================================================
#  send_kakao.ps1 — 카카오톡 일일 요약 발송
#  실행: powershell -ExecutionPolicy Bypass -File send_kakao.ps1
# =====================================================
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# ── 1. token.txt 읽기 ──────────────────────────────
$tokenFile = Join-Path $scriptDir "token.txt"
if (-not (Test-Path $tokenFile)) {
    Write-Host "❌ token.txt 파일을 찾을 수 없습니다: $tokenFile"
    exit 1
}
$tokens = @{}
Get-Content $tokenFile -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^(\w+)\s*=\s*(.+)$") { $tokens[$Matches[1]] = $Matches[2].Trim() }
}
$restApiKey   = $tokens["KAKAO_REST_API_KEY"]
$clientSecret = $tokens["KAKAO_CLIENT_SECRET"]
$refreshToken = $tokens["KAKAO_REFRESH_TOKEN"]

# ── 2. Access Token 갱신 ───────────────────────────
Write-Host "🔑 Access Token 갱신 중..."
try {
    $tokenResp = Invoke-RestMethod -Uri "https://kauth.kakao.com/oauth/token" -Method Post `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "grant_type=refresh_token&client_id=$restApiKey&refresh_token=$refreshToken&client_secret=$clientSecret"
} catch {
    Write-Host "❌ 토큰 갱신 실패: $_"
    exit 1
}
$accessToken = $tokenResp.access_token

# Refresh Token이 갱신된 경우 token.txt에 저장
if ($tokenResp.refresh_token) {
    $content = Get-Content $tokenFile -Encoding UTF8
    $content = $content -replace "KAKAO_REFRESH_TOKEN = .+", "KAKAO_REFRESH_TOKEN = $($tokenResp.refresh_token)"
    Set-Content $tokenFile $content -Encoding UTF8
    Write-Host "🔄 Refresh Token 갱신 저장 완료"
}

# ── 3. daily_summary.json 읽기 ────────────────────
$localPath     = Join-Path $scriptDir "daily_summary.json"
$downloadsPath = Join-Path $env:USERPROFILE "Downloads\daily_summary.json"

if (Test-Path $localPath) {
    $summaryPath = $localPath
} elseif (Test-Path $downloadsPath) {
    $summaryPath = $downloadsPath
    Copy-Item $downloadsPath $localPath  # 앞으로는 로컬에서 읽도록 복사
} else {
    Write-Host "❌ daily_summary.json 파일을 찾을 수 없습니다."
    Write-Host "   앱 설정 탭에서 '오늘 요약 저장하기' 버튼을 먼저 눌러주세요."
    exit 1
}

$summary  = Get-Content $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$date     = $summary.date
$tasks    = $summary.tasks
$messages = $summary.messages

# ── 4. 메시지 작성 ─────────────────────────────────
$lines = @()
$lines += "🏠 우리 집 히어로 일일 요약"
$lines += "📅 $date"
$lines += ""

if ($tasks.Count -gt 0) {
    $lines += "✅ 오늘 완료한 집안일 ($($tasks.Count)건)"
    $grouped = $tasks | Group-Object memberName
    foreach ($g in $grouped) {
        $chores = ($g.Group | ForEach-Object { "$($_.choreEmoji)$($_.choreName)" }) -join " · "
        $lines += "$($g.Group[0].memberEmoji) $($g.Name): $chores"
    }
} else {
    $lines += "✅ 오늘은 완료한 집안일이 없어요"
}

$lines += ""
if ($messages.Count -gt 0) {
    $lines += "💬 가족 메시지 ($($messages.Count)건)"
    foreach ($msg in $messages) {
        $line = "$($msg.fromEmoji) $($msg.from) → $($msg.to): $($msg.text)"
        if ($line.Length -gt 45) { $line = $line.Substring(0, 42) + "..." }
        $lines += $line
    }
} else {
    $lines += "💬 오늘은 가족 메시지가 없어요"
}

$msgText = $lines -join "`n"
if ($msgText.Length -gt 200) { $msgText = $msgText.Substring(0, 197) + "..." }

# ── 5. 카카오톡 발송 ───────────────────────────────
Write-Host "📨 카카오톡 발송 중..."
$template = '{{"object_type":"text","text":{0},"link":{{"web_url":"https://cejingme.github.io/forhome","mobile_web_url":"https://cejingme.github.io/forhome"}}}}' `
    -f (ConvertTo-Json $msgText -Compress)

$encodedTemplate = [System.Net.WebUtility]::UrlEncode($template)

try {
    $result = Invoke-RestMethod -Uri "https://kapi.kakao.com/v2/api/talk/memo/default/send" -Method Post `
        -Headers @{ Authorization = "Bearer $accessToken" } `
        -ContentType "application/x-www-form-urlencoded" `
        -Body "template_object=$encodedTemplate"
    Write-Host "✅ 카카오톡 발송 완료!"
    Write-Host $msgText
} catch {
    Write-Host "❌ 카카오톡 발송 실패: $_"
    exit 1
}
