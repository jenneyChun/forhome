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

Write-Host "ForHome Firebase hosting, Firestore, and backup structure tests"

@("code", "server", "data", "data\exports", "log", "docs", "docs\session", "scripts", "tests", "tests\e2e", "tests\fixtures", "tests\powershell", ".github", ".github\workflows") |
    ForEach-Object { Assert-Dir $_ }

@(
    "code\index.html",
    ".firebaserc",
    "firebase.json",
    "firestore.rules",
    ".github\workflows\firestore-backup.yml",
    "scripts\firestore-backup.js",
    "server\server.ps1",
    "server\send_kakao.ps1",
    "server\setup_scheduler.ps1",
    "server\start_server.bat",
    "tests\playwright.config.js",
    "tests\e2e\app.spec.js",
    "tests\fixtures\backup-state.json",
    "docs\session\2026-06-03-02-firebase-hosting-firestore-github-backup.md",
    "docs\session\2026-06-03-03-review-proof-tomorrow-ui.md"
) | ForEach-Object { Assert-File $_ }

$docs = @(Get-ChildItem -Path (Join-Path $repoRoot "docs") -Filter "*.md" -File)
Assert-True ($docs.Count -gt 0) "requirements document exists in docs"

@("server\server.ps1", "server\send_kakao.ps1", "server\setup_scheduler.ps1") | ForEach-Object {
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
$indexText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "code\index.html")
$rulesText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "firestore.rules")
$workflowText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot ".github\workflows\firestore-backup.yml")
$backupScriptText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "scripts\firestore-backup.js")

Assert-True ($serverText -notmatch "app_state\.json") "server does not use app_state.json"
Assert-True ($serverText -notmatch "Initialize-Database") "static test server does not initialize PostgreSQL"
Assert-True ($serverText -match "static-test") "server health reports static test mode"
Assert-True ($indexText -match "firebase\.initializeApp") "client initializes Firebase"
Assert-True ($indexText -match 'families/\$\{FIRESTORE_FAMILY_ID\}/state/app') "client targets Firestore state document"
Assert-True ($indexText -match "createTestStorageProvider") "client has Playwright storage mock"
Assert-True ($indexText -match "LOCAL_HOSTS") "client defaults localhost to local mock storage"
Assert-True ($indexText -notmatch "/api/state") "client does not use local state API"
Assert-True ($indexText -match "proofPhoto") "client supports photo proof input"
Assert-True ($indexText -match "verificationStatus") "client tracks task verification status"
Assert-True ($indexText -match "approveTask") "client supports reviewer approval"
Assert-True ($indexText -match "tomorrowPlans") "client tracks tomorrow plans"
Assert-True ($rulesText -match "admin@forhome\.local") "Firestore rules allow seeded admin auth email"
Assert-True ($workflowText -match "10 15 \* \* \*") "GitHub Actions backup runs daily at KST midnight window"
Assert-True ($backupScriptText -match "FIREBASE_SERVICE_ACCOUNT_JSON") "backup script reads Firebase service account secret"

$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $dryRunDir = Join-Path $repoRoot "log\backup-dry-run"
    & node (Join-Path $repoRoot "scripts\firestore-backup.js") --fixture (Join-Path $repoRoot "tests\fixtures\backup-state.json") --date "2026-06-03" --out-dir $dryRunDir
    Assert-True (Test-Path (Join-Path $dryRunDir "data\backups\2026-06-03\state.json")) "backup dry run writes dated state JSON"
    Assert-True (Test-Path (Join-Path $dryRunDir "reports\daily\2026-06-03.md")) "backup dry run writes dated markdown report"
} else {
    Write-Host "SKIP backup dry run because node is not available."
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Test failures: $($failures.Count)"
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host ""
Write-Host "All available tests passed."
