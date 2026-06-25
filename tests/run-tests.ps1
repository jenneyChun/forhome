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

function Assert-MissingFile($RelativePath) {
    Assert-True (-not (Test-Path (Join-Path $repoRoot $RelativePath))) "file removed: $RelativePath"
}

function Assert-Dir($RelativePath) {
    Assert-True (Test-Path (Join-Path $repoRoot $RelativePath) -PathType Container) "directory exists: $RelativePath"
}

Write-Host "ForHome PostgreSQL API, backup, and structure tests"

@("code", "server", "server\sql", "data", "data\exports", "log", "docs", "docs\session", "scripts", "tests", "tests\e2e", "tests\fixtures", "tests\powershell", "Report", "Prompting", ".github", ".github\workflows") |
    ForEach-Object { Assert-Dir $_ }

@(
    "code\web\index.html",
    "code\mobile\index.html",
    "code\shared\forhome-core.js",
    "code\shared\tokens.css",
    "server\server.ps1",
    "server\db.ps1",
    "server\sql\schema.sql",
    "scripts\postgresql-backup.ps1",
    ".github\workflows\postgresql-backup.yml",
    ".github\workflows\codex-kakao-notify.yml",
    "server\send_kakao.ps1",
    "server\send_codex_update.ps1",
    "server\setup_scheduler.ps1",
    "server\start_server.bat",
    "server\kakao-recipients.example.json",
    "server\briefing.env.example.ps1",
    "docs\auth-invitation-flow.ko.md",
    "docs\postgresql-transition-plan.ko.md",
    "docs\codex-kakao-notify.ko.md",
    "tests\playwright.config.js",
    "tests\e2e\app.spec.js",
    "tests\e2e\login-navigation.spec.js",
    "tests\fixtures\backup-state.json",
    "tests\powershell\login-performance.ps1"
) | ForEach-Object { Assert-File $_ }

Assert-MissingFile "scripts\firestore-backup.js"
Assert-MissingFile ".github\workflows\firestore-backup.yml"

$docs = @(Get-ChildItem -Path (Join-Path $repoRoot "docs") -Filter "*.md" -File)
Assert-True ($docs.Count -gt 0) "requirements document exists in docs"

@(
    "server\server.ps1",
    "server\db.ps1",
    "server\send_kakao.ps1",
    "server\send_codex_update.ps1",
    "server\setup_scheduler.ps1",
    "scripts\postgresql-backup.ps1"
) | ForEach-Object {
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
$indexText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "code\shared\forhome-core.js")
$webText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "code\web\index.html")
$workflowText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot ".github\workflows\postgresql-backup.yml")
$backupScriptText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "scripts\postgresql-backup.ps1")
$sendKakaoText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "server\send_kakao.ps1")
$briefingEnvText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "server\briefing.env.example.ps1")
$transitionDocText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "docs\postgresql-transition-plan.ko.md")
$packageText = Get-Content -Raw -Encoding UTF8 (Join-Path $repoRoot "package.json")

Assert-True ($serverText -match "Get-DbHealth") "server health checks PostgreSQL"
Assert-True ($serverText -match "/api/auth/register-owner") "server exposes owner registration API"
Assert-True ($serverText -match "/api/auth/login") "server exposes login API"
Assert-True ($serverText -match "/api/session") "server exposes session API"
Assert-True ($serverText -match "/api/invites") "server exposes invitation API"
Assert-True ($serverText -match "Set-Cookie") "server issues cookie headers"
Assert-True ($serverText -match "HttpOnly") "server session cookie is httpOnly"
Assert-True ($serverText -match "Get-SurfaceClientRoot") "server routes static files by host"
Assert-True ($serverText -match "m\.localhost") "server documents mobile host in CORS origins"
Assert-True ($serverText -match "FORHOME_COOKIE_DOMAIN") "server supports shared cookie domain"

Assert-True ($dbText -match "pbkdf2_sha256") "database layer hashes passwords with PBKDF2-SHA256"
Assert-True ($dbText -match "token_hash") "database layer stores session token hash"
Assert-True ($dbText -match "Register-Owner") "database layer creates owner households"
Assert-True ($dbText -match "New-DbInvitation") "database layer creates invitations"
Assert-True ($dbText -match "Accept-DbInvitation") "database layer accepts invitations"

@(
    "users",
    "households",
    "household_members",
    "sessions",
    "invitations",
    "chores",
    "task_entries",
    "task_approvals",
    "care_items",
    "care_assignments",
    "care_sessions",
    "tomorrow_plans",
    "messages",
    "settings"
) | ForEach-Object {
    Assert-True ($schemaText -match "CREATE TABLE IF NOT EXISTS $_") "schema defines table: $_"
}

Assert-True ($indexText -match "createPostgresApiProvider") "client uses PostgreSQL API provider"
Assert-True ($indexText -match "/api/session") "client checks server session"
Assert-True ($indexText -match "/api/auth/login") "client logs in through server API"
Assert-True ($indexText -match "/api/state") "client reads and writes state through server API"
Assert-True ($indexText -match "createTestStorageProvider") "client keeps Playwright storage mock"
Assert-True ($indexText -notmatch "firebase\.initializeApp") "client no longer initializes Firebase"
Assert-True ($serverText -match "/api/state/summary") "server exposes state summary API"
Assert-True ($serverText -match "/api/state/version") "server exposes state version API"
Assert-True ($serverText -match "/api/tasks/.*/proof") "server exposes task proof API"
Assert-True ($indexText -match "loadSummaryThenFull") "client loads summary before full state"
Assert-True ($dbText -match "Invoke-PsqlCsvBatch") "database layer batches PostgreSQL reads"
Assert-True ($webText -match 'data-testid="app-shell"') "client exposes app-shell test id for login navigation tests"
Assert-True ($webText -match 'data-surface="web"') "web shell marks web surface"
Assert-True ($webText -match "/shared/forhome-core.js") "web shell loads shared core"

Assert-True ($workflowText -match "PostgreSQL daily backup") "GitHub Actions backup is PostgreSQL-based"
Assert-True ($workflowText -match "PGHOST") "GitHub Actions reads PostgreSQL connection secrets"
Assert-True ($workflowText -match "postgresql-backup\.ps1") "GitHub Actions uses PostgreSQL backup script"
Assert-True ($backupScriptText -match "Get-DbState") "backup script reads PostgreSQL state"
Assert-True ($backupScriptText -match "Fixture") "backup script supports fixture dry-run"
Assert-True ($sendKakaoText -match "postgresql-backup\.ps1") "Kakao briefing uses PostgreSQL backup script"
Assert-True ($sendKakaoText -notmatch "firestore-backup\.js") "Kakao briefing no longer uses Firestore backup script"
Assert-True ($briefingEnvText -match "PGHOST") "briefing env example documents PostgreSQL settings"
Assert-True ($briefingEnvText -notmatch "FIREBASE_SERVICE_ACCOUNT_JSON") "briefing env example no longer documents Firebase service account"
Assert-True ($packageText -notmatch "firebase-admin") "package.json no longer depends on firebase-admin"
Assert-True ($transitionDocText -match "createPostgresApiProvider") "transition document describes PostgreSQL frontend provider"

$dryRunDir = Join-Path $repoRoot "log\backup-dry-run"
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\postgresql-backup.ps1") -Fixture (Join-Path $repoRoot "tests\fixtures\backup-state.json") -Date "2026-06-03" -OutDir $dryRunDir
Assert-True (Test-Path (Join-Path $dryRunDir "data\backups\2026-06-03\state.json")) "backup dry run writes dated state JSON"
Assert-True (Test-Path (Join-Path $dryRunDir "reports\daily\2026-06-03.md")) "backup dry run writes dated markdown report"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\postgresql-backup.ps1") -Fixture (Join-Path $repoRoot "tests\fixtures\backup-state.json") -Date "2026-06-04" -Briefing -OutFile (Join-Path $dryRunDir "morning_briefing.json")
Assert-True (Test-Path (Join-Path $dryRunDir "morning_briefing.json")) "briefing dry run writes morning briefing JSON"

if ($env:RUN_DB_TESTS -eq "1") {
    $health = & powershell -NoProfile -ExecutionPolicy Bypass -Command "& { . '$repoRoot\server\db.ps1'; Get-DbHealth | ConvertTo-Json -Compress }"
    Assert-True ($health -match '"storage":"postgresql"') "live PostgreSQL health returns PostgreSQL storage"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "tests\powershell\login-performance.ps1")
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("login-performance.ps1 failed")
    }
} else {
    Write-Host "SKIP live PostgreSQL checks because RUN_DB_TESTS is not 1."
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "Test failures: $($failures.Count)"
    $failures | ForEach-Object { Write-Host "- $_" }
    exit 1
}

Write-Host ""
Write-Host "All available tests passed."
