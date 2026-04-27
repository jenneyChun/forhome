# =====================================================
#  setup_scheduler.ps1 — Windows 작업 스케줄러 등록
#  최초 1회만 실행 (관리자 권한으로 실행하세요)
# =====================================================
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ps1Path    = Join-Path $scriptDir "send_kakao.ps1"
$taskName   = "ForHouse_DailySummary"
$sendTime   = "23:55"   # 매일 발송 시각 (변경 가능)

$action  = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""

$trigger = New-ScheduledTaskTrigger -Daily -At $sendTime

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action   $action `
        -Trigger  $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force | Out-Null

    Write-Host "✅ 스케줄러 등록 완료!"
    Write-Host "   작업 이름 : $taskName"
    Write-Host "   발송 시각 : 매일 $sendTime"
    Write-Host "   스크립트  : $ps1Path"
    Write-Host ""
    Write-Host "확인: 작업 스케줄러 앱 → 작업 스케줄러 라이브러리 → ForHouse_DailySummary"
} catch {
    Write-Host "❌ 등록 실패: $_"
    Write-Host "   관리자 권한으로 PowerShell을 열고 다시 실행해주세요."
}
