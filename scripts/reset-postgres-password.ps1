param(
    [string]$Password = "forhome"
)

$ErrorActionPreference = "Stop"
$pgBin = "C:\Program Files\PostgreSQL\17\bin"
$dataDir = "C:\Program Files\PostgreSQL\17\data"
$serviceName = "postgresql-x64-17"

if (-not (Test-Path (Join-Path $pgBin "postgres.exe"))) {
    throw "PostgreSQL 17 was not found at $pgBin"
}

Write-Host "Stopping PostgreSQL service..."
Stop-Service $serviceName -Force

$sql = "ALTER USER postgres WITH PASSWORD '$($Password.Replace("'", "''"))';"
Write-Host "Resetting postgres user password..."

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $pgBin "postgres.exe"
$psi.Arguments = "--single -D `"$dataDir`" postgres"
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$process = [System.Diagnostics.Process]::Start($psi)
$process.StandardInput.WriteLine($sql)
$process.StandardInput.Close()
$process.WaitForExit()

if ($process.ExitCode -ne 0) {
    $stderr = $process.StandardError.ReadToEnd()
    throw "Password reset failed: $stderr"
}

Write-Host "Starting PostgreSQL service..."
Start-Service $serviceName
Write-Host "Password reset complete. Use PGPASSWORD=$Password in data\db.env.ps1"
