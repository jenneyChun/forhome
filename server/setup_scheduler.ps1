# Registers the daily Kakao summary task in Windows Task Scheduler.
# Run once from an elevated PowerShell window.
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ps1Path = Join-Path $scriptDir "send_kakao.ps1"
$taskName = "ForHome_DailySummary"
$sendTime = "23:55"

$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1Path`""

$trigger = New-ScheduledTaskTrigger -Daily -At $sendTime

$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -StartWhenAvailable

try {
    Register-ScheduledTask `
        -TaskName $taskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force | Out-Null

    Write-Host "Task Scheduler registration complete."
    Write-Host "Task name : $taskName"
    Write-Host "Send time : daily $sendTime"
    Write-Host "Script    : $ps1Path"
} catch {
    Write-Host "Registration failed: $_"
    Write-Host "Run PowerShell as administrator and try again."
}
