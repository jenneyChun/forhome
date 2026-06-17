# Copy this file to server\briefing.env.ps1 and fill local-only secrets.
$env:FORHOME_APP_URL = "http://localhost:8080"

# PostgreSQL connection used by scripts\postgresql-backup.ps1.
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"
$env:PGPASSWORD = ""

# Local dry-runs can point to a fixture instead of PostgreSQL.
# $env:POSTGRES_BRIEFING_FIXTURE = "C:\path\to\backup-state.json"

# Optional defaults shared by recipients that do not set these values directly.
# $env:KAKAO_REST_API_KEY = ""
# $env:KAKAO_CLIENT_SECRET = ""
