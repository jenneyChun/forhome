$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True($Condition, $Message) {
    if (-not $Condition) {
        $script:failures.Add($Message)
        Write-Host "FAIL $Message"
    } else {
        Write-Host "PASS $Message"
    }
}

. (Join-Path $repoRoot "server\db.ps1")

Write-Host "ForHome login performance tests (RUN_DB_TESTS=1)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Initialize-Database
$sw.Stop()
Assert-True ($sw.ElapsedMilliseconds -lt 30000) "Initialize-Database warm-up completes under 30s (took $($sw.ElapsedMilliseconds)ms)"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = Login-DbUser "admin" "admin1234"
$sw.Stop()
Assert-True ($sw.ElapsedMilliseconds -lt 5000) "Login-DbUser completes under 5s (took $($sw.ElapsedMilliseconds)ms)"
Assert-True ($null -ne $result.session.accountId) "Login-DbUser returns session.accountId"
Assert-True ($null -ne $result.session.householdName) "Login-DbUser returns session.householdName bootstrap"

$token = $result.token
$session = Get-DbSession $token
Assert-True ($null -ne $session) "Login session is readable"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$state = Get-DbState $session.householdId
$sw.Stop()
Assert-True ($sw.ElapsedMilliseconds -lt 5000) "Get-DbState completes under 5s (took $($sw.ElapsedMilliseconds)ms)"
Assert-True ($null -ne $state.householdName) "Get-DbState returns householdName"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$summary = Get-DbStateSummary $session.householdId
$sw.Stop()
Assert-True ($sw.ElapsedMilliseconds -lt 3000) "Get-DbStateSummary completes under 3s (took $($sw.ElapsedMilliseconds)ms)"
Assert-True ($null -ne $summary.householdName) "Get-DbStateSummary returns householdName"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$version = Get-DbStateVersion
$sw.Stop()
Assert-True ($sw.ElapsedMilliseconds -lt 1000) "Get-DbStateVersion completes under 1s (took $($sw.ElapsedMilliseconds)ms)"

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Login performance failures: $($failures.Count)"
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host ""
Write-Host "All login performance tests passed."
