$ErrorActionPreference = "Stop"
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$failures = New-Object System.Collections.Generic.List[string]

function Assert-True($Condition, $Message) {
    if (-not $Condition) {
        $script:failures.Add($Message)
        Write-Host "FAIL $Message"
    } else {
        Write-Host "PASS $Message"
    }
}

function Assert-File($RelativePath) {
    Assert-True (Test-Path (Join-Path $repoRoot $RelativePath)) "file exists: $RelativePath"
}

function Assert-Dir($RelativePath) {
    Assert-True (Test-Path (Join-Path $repoRoot $RelativePath) -PathType Container) "directory exists: $RelativePath"
}

Write-Host "ForHome structure and server tests"

@("code", "server", "server\sql", "data", "data\exports", "log", "docs", "docs\session", "tests", "tests\e2e", "tests\powershell") |
    ForEach-Object { Assert-Dir $_ }

@(
    "code\index.html",
    "server\server.ps1",
    "server\db.ps1",
    "server\sql\schema.sql",
    "server\send_kakao.ps1",
    "server\setup_scheduler.ps1",
    "server\start_server.bat",
    "data\db.env.example.ps1",
    "tests\playwright.config.js",
    "tests\e2e\app.spec.js"
) | ForEach-Object { Assert-File $_ }

$docs = @(Get-ChildItem -Path (Join-Path $repoRoot "docs") -Filter "*.md" -File)
Assert-True ($docs.Count -gt 0) "requirements document exists in docs"

@("server\server.ps1", "server\db.ps1", "server\send_kakao.ps1", "server\setup_scheduler.ps1") | ForEach-Object {
    $path = Join-Path $repoRoot $_
    try {
        [scriptblock]::Create((Get-Content -Raw -Encoding UTF8 $path)) | Out-Null
        Write-Host "PASS parse: $_"
    } catch {
        $failures.Add("parse failed: $_ :: $($_.Exception.Message)")
        Write-Host "FAIL parse: $_"
    }
}

$serverText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "server\server.ps1")
$dbText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "server\db.ps1")
$schemaText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "server\sql\schema.sql")

Assert-True ($serverText -notmatch "app_state\.json") "server does not use app_state.json"
Assert-True ($serverText -match "Get-DbState") "server reads state from PostgreSQL layer"
Assert-True ($serverText -match "Set-DbState") "server writes state through PostgreSQL layer"
Assert-True ($dbText -match "psql") "database layer uses PostgreSQL psql client"
Assert-True ($schemaText -match "CREATE TABLE IF NOT EXISTS members") "schema contains members table"
Assert-True ($schemaText -match "CREATE TABLE IF NOT EXISTS history") "schema contains history table"
Assert-True ($schemaText -match "CREATE TABLE IF NOT EXISTS messages") "schema contains messages table"

if ($env:RUN_DB_TESTS -eq "1") {
    Write-Host "RUN_DB_TESTS=1, attempting PostgreSQL integration check"
    . (Join-Path $repoRoot "server\db.ps1")
    Initialize-Database
    $state = Get-DbState
    Assert-True (@($state.members).Count -gt 0) "PostgreSQL state has seeded members"
    Assert-True (@($state.chores).Count -gt 0) "PostgreSQL state has seeded chores"
} else {
    Write-Host "SKIP PostgreSQL integration check. Set RUN_DB_TESTS=1 after PostgreSQL/psql is installed."
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Test failures: $($failures.Count)"
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host ""
Write-Host "All available tests passed."
