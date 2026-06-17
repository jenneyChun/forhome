param(
    [string]$Date = (Get-Date -Format "yyyy-MM-dd"),
    [string]$OutDir,
    [switch]$Briefing,
    [string]$OutFile,
    [string]$Fixture
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir ".."))
if (-not $OutDir) { $OutDir = $RepoRoot }

. (Join-Path $RepoRoot "server\db.ps1")

function Ensure-Directory($Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Read-BackupState {
    if ($Fixture) {
        return (Get-Content -Raw -Encoding UTF8 $Fixture | ConvertFrom-Json)
    }
    return Get-DbState
}

function Get-MemberName($State, $MemberId) {
    $member = @($State.members) | Where-Object { $_.id -eq $MemberId } | Select-Object -First 1
    if ($member) { return $member.name }
    return $MemberId
}

function New-DailyReport($State, $DateText) {
    $approved = @($State.history) | Where-Object { $_.verificationStatus -eq "approved" }
    $messages = @($State.messages)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# ForHome Daily Report - $DateText")
    $lines.Add("")
    $lines.Add("- Version: $($State.version)")
    $lines.Add("- Approved tasks: $($approved.Count)")
    $lines.Add("- Messages: $($messages.Count)")
    $lines.Add("")
    $lines.Add("## Approved Tasks")
    if ($approved.Count -eq 0) {
        $lines.Add("")
        $lines.Add("- None")
    } else {
        foreach ($entry in $approved) {
            $name = Get-MemberName $State $entry.memberId
            $lines.Add("- ${name}: $($entry.choreName) (+$($entry.xpEarned) XP)")
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function New-MorningBriefing($State, $DateText) {
    $approved = @($State.history) | Where-Object { $_.verificationStatus -eq "approved" }
    $plans = @($State.tomorrowPlans) | Where-Object { $_.requestStatus -eq "accepted" -or $_.status -eq "open" }
    $text = "ForHome $DateText briefing`nApproved tasks: $($approved.Count)`nOpen plans: $($plans.Count)"
    return [pscustomobject]@{
        date = $DateText
        text = $text
        approvedTaskCount = $approved.Count
        openPlanCount = $plans.Count
        storage = "postgresql"
    }
}

$state = Read-BackupState

if ($Briefing) {
    if (-not $OutFile) {
        $OutFile = Join-Path $OutDir "data\exports\morning_briefing.json"
    }
    Ensure-Directory ([System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($OutFile)))
    New-MorningBriefing $state $Date | ConvertTo-Json -Depth 20 | Out-File $OutFile -Encoding utf8
    Write-Host "Wrote briefing: $OutFile"
    exit 0
}

$backupDir = Join-Path $OutDir "data\backups\$Date"
$reportDir = Join-Path $OutDir "reports\daily"
Ensure-Directory $backupDir
Ensure-Directory $reportDir

$statePath = Join-Path $backupDir "state.json"
$reportPath = Join-Path $reportDir "$Date.md"

$state | ConvertTo-Json -Depth 50 | Out-File $statePath -Encoding utf8
New-DailyReport $state $Date | Out-File $reportPath -Encoding utf8

Write-Host "Wrote state: $statePath"
Write-Host "Wrote report: $reportPath"
