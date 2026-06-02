# ForHome

ForHome is a local family chore web app. The PC runs the server, PostgreSQL stores the app data, and browsers on the same network can use the app from desktop or mobile.

## Folder Layout

- `code/`: browser client code
- `server/`: PowerShell server, PostgreSQL access layer, Kakao scripts, SQL schema
- `data/`: local runtime config and generated exports
- `log/`: local runtime logs and Playwright reports
- `tests/`: structure tests and Playwright E2E tests
- `docs/`: requirements and Codex session notes

## PostgreSQL Setup

Install PostgreSQL and make sure `psql` is available from PowerShell.

Copy the example config:

```powershell
Copy-Item data\db.env.example.ps1 data\db.env.ps1
```

Edit `data\db.env.ps1` for your PostgreSQL connection:

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your-password"
```

The server creates the `forhome` database when possible, applies `server/sql/schema.sql`, and seeds default family members, accounts, and chores.

## Run

```powershell
server\start_server.bat
```

Then open:

- PC: `http://localhost:8080`
- Mobile: use the LAN URL printed by the server window

Default accounts:

- `admin` / `admin1234`
- `mom` / `mom1234`
- `dad` / `dad1234`
- `son` / `son1234`

## Tests

Run always-available structure and syntax tests:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

After PostgreSQL and `psql` are configured, run DB integration checks too:

```powershell
$env:RUN_DB_TESTS = "1"
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Playwright E2E requires Node/npm and browser binaries:

```powershell
npm install
npx playwright install chromium
npm run test:e2e
```
