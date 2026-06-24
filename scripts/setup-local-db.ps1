param(
    [string]$PostgresPassword = "",
    [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$DbConfigPath = Join-Path $RepoRoot "data\db.env.ps1"
$ExamplePath = Join-Path $RepoRoot "data\db.env.example.ps1"

. (Join-Path $RepoRoot "server\db.ps1")

function Write-Step($Message) {
    Write-Host ""
    Write-Host "==> $Message"
}

function Test-PostgresService {
    $service = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $service) { return $null }
    return $service
}

function Install-PostgresClient {
    if (Find-PsqlPath) { return }
    if ($SkipInstall) {
        throw "psql was not found. Install PostgreSQL, then re-run this script."
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget is unavailable. Install PostgreSQL 17 manually from https://www.postgresql.org/download/windows/ and re-run this script."
    }
    Write-Step "Installing PostgreSQL 17 with winget"
    winget install PostgreSQL.PostgreSQL.17 --accept-package-agreements --accept-source-agreements
    if (-not (Find-PsqlPath)) {
        throw "PostgreSQL install finished but psql is still missing. Re-open the terminal or add PostgreSQL\bin to PATH."
    }
}

function Test-PostgresPassword($Password) {
    if (-not $Password) { return $false }
    $psql = Find-PsqlPath
    $prev = $env:PGPASSWORD
    $env:PGPASSWORD = $Password
    try {
        $output = & $psql -w -X -q -t -A -h localhost -p 5432 -U postgres -d postgres -c "SELECT 1" 2>&1
        return ($LASTEXITCODE -eq 0 -and (($output -join "").Trim()) -eq "1")
    } finally {
        if ($null -eq $prev) { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
        else { $env:PGPASSWORD = $prev }
    }
}

function Resolve-PostgresPassword {
    param([string]$Provided)

    if ($Provided -and (Test-PostgresPassword $Provided)) { return $Provided }

    foreach ($candidate in @("forhome", "postgres")) {
        if ($candidate -eq $Provided) { continue }
        if (Test-PostgresPassword $candidate) {
            Write-Host "Detected postgres password: $candidate"
            return $candidate
        }
    }

    if ($Provided) {
        throw "PostgreSQL password authentication failed. Run scripts\reset-postgres-password.ps1 as Administrator or pass -PostgresPassword with the correct value."
    }
    return $null
}

function Write-DbConfig($Password) {
    if (-not (Test-Path $ExamplePath)) {
        throw "Missing example config: $ExamplePath"
    }
    $lines = Get-Content -Path $ExamplePath -Encoding UTF8
    if ($Password) {
        $lines += '$env:PGPASSWORD = "' + ($Password.Replace('"', '`"')) + '"'
    }
    $content = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    if (-not (Test-Path (Split-Path $DbConfigPath -Parent))) {
        New-Item -ItemType Directory -Force -Path (Split-Path $DbConfigPath -Parent) | Out-Null
    }
    Set-Content -Path $DbConfigPath -Value $content -Encoding UTF8
}

Write-Host "ForHome local PostgreSQL setup"
Write-Host "Repository: $RepoRoot"

Install-PostgresClient
$psqlPath = Find-PsqlPath
Write-Step "Using psql at $psqlPath"

$service = Test-PostgresService
if ($service -and $service.Status -ne "Running") {
    Write-Step "Starting PostgreSQL service: $($service.Name)"
    Start-Service $service.Name
}

if (-not $PostgresPassword) {
    $PostgresPassword = Resolve-PostgresPassword ""
}

$PostgresPassword = Resolve-PostgresPassword $PostgresPassword

if (-not $PostgresPassword) {
    $secure = Read-Host "Enter postgres user password (leave blank if trust auth is enabled)" -AsSecureString
    if ($secure.Length -gt 0) {
        $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $PostgresPassword = Resolve-PostgresPassword ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr))
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
    } else {
        throw "PostgreSQL password is required. Run scripts\reset-postgres-password.ps1 as Administrator or pass -PostgresPassword."
    }
}

Write-Step "Writing $DbConfigPath"
Write-DbConfig $PostgresPassword

Write-Step "Initializing database schema and default accounts"
Initialize-Database

Write-Host ""
Write-Host "Setup complete."
Write-Host "Start the app with:"
Write-Host "  npm run dev:local"
Write-Host "or"
Write-Host "  server\start_server.bat"
Write-Host ""
Write-Host "Open http://localhost:8080 and log in with admin / admin1234"
