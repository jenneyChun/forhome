# Copy this file to data\db.env.ps1 and edit the values.
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"

# Required for password auth. Local dev: run `npm run setup:db` (auto-detects postgres/forhome).
# Docker Compose uses forhome; a fresh Windows PostgreSQL install often uses postgres.
# $env:PGPASSWORD = "forhome"
