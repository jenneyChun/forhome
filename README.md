# ForHome

ForHome is a family chore, care, tomorrow-plan, and message web app. Production and persistent data live in PostgreSQL. The browser never connects to PostgreSQL directly; it calls the PowerShell API server in `server/server.ps1`.

## Folder Layout

- `code/`: browser client code
  - `code/web/`: PC web shell
  - `code/mobile/`: mobile shell (`m.` host)
  - `code/shared/`: shared JS/CSS and core logic
- `server/`: PowerShell static file, auth, session, and PostgreSQL API server
- `server/sql/schema.sql`: normalized PostgreSQL schema
- `scripts/`: PostgreSQL backup and automation scripts
- `data/`: local DB config, generated exports, and backup output
- `log/`: local runtime logs and Playwright reports
- `tests/`: structure tests, fixtures, and Playwright E2E tests
- `docs/`: requirements, design notes, and Codex session notes
- `Report/`: Cursor/Codex work and status reports
- `Prompting/`: reusable prompts and agent instructions

## PostgreSQL Setup

PostgreSQL server and the `psql` client must be available. Provide connection settings through environment variables or `data/db.env.ps1`.

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your-password"
```

When the server starts, `server/db.ps1` applies `server/sql/schema.sql` and prepares seed data and default local accounts.

Default local accounts:

```text
admin / admin1234
mom / mom1234
dad / dad1234
son / son1234
```

Passwords are stored as `pbkdf2_sha256$iterations$salt$hash`. Browser sessions use an `httpOnly` cookie, while PostgreSQL stores only the session token hash.

## Local Server

For local development and Playwright checks, run:

```bash
npm run dev:local
```

If Node/npm is not installed, start the same server directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080
```

Then open:

- Web: `http://localhost:8080`
- Mobile: `http://m.localhost:8080`
- LAN: use the URLs printed by the server window

The server provides static files and API routes:

```text
GET  /api/health
POST /api/auth/register-owner
POST /api/auth/login
POST /api/auth/logout
GET  /api/session
GET  /api/state
PUT  /api/state
POST /api/invites
GET  /api/invites/:id
POST /api/invites/:id
```

## Web and Mobile Clients

ForHome ships **two separate browser clients** on the same API server (port 8080). The server picks the shell from the request `Host` header — no `?surface=` query string.

| Client | Local URL | Static root | Layout |
|--------|-----------|-------------|--------|
| Web (PC) | `http://localhost:8080` | `code/web/` | Left sidebar tabs, 12-column grid |
| Mobile | `http://m.localhost:8080` | `code/mobile/` | Bottom tab bar, single column |

**Shared assets**

| Path | Role |
|------|------|
| `code/shared/forhome-core.js` | State, API providers, render functions, events (`ForHomeApp.boot`) |
| `code/shared/tokens.css` | urichib design tokens and shared component styles |
| `code/shared/web.css` | PC-only layout overrides |
| `code/shared/mobile.css` | Mobile-only layout (fixed bottom tabs) |

Both shells expose the same five tabs and `data-testid` values: briefing (home), tasks, badges, calendar, settings.

In production, point `https://<domain>` and `https://m.<domain>` at the same server.

To share login between web and mobile subdomains locally, set in `data/db.env.ps1`:

```powershell
$env:FORHOME_COOKIE_DOMAIN = ".localhost"
```

Without this, you must log in separately on `localhost` and `m.localhost`.

Use browser mock storage only for Playwright or local UI tests:

```text
http://localhost:8080/?storage=test
http://m.localhost:8080/?storage=test
```

Implementation details: [`Report/260625_web-mobile-client-split.ko.md`](Report/260625_web-mobile-client-split.ko.md)

## Invitation-Based Signup

The first registrant creates a household as the `owner` representative hero. That person can invite others with an invite URL, QR payload, or short invite code. Invitees join as either a `hero` or `care_member`.

See `docs/auth-invitation-flow.ko.md` and `docs/postgresql-transition-plan.ko.md` for details.

## GitHub Backup

The workflow `.github/workflows/postgresql-backup.yml` runs daily at `15:10 UTC`, which is `00:10 KST`, and writes:

```text
data/backups/YYYY-MM-DD/state.json
reports/daily/YYYY-MM-DD.md
```

Add PostgreSQL connection secrets before enabling the workflow:

```text
PGHOST
PGPORT
PGDATABASE
PGUSER
PGPASSWORD
```

Local dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\postgresql-backup.ps1 -Fixture tests\fixtures\backup-state.json -Date 2026-06-03 -OutDir log\backup-dry-run
```

## Morning Briefing

The local Windows scheduler can send the 07:00 KST ForHome briefing through Kakao memo-to-me.

Copy and fill these local-only files:

```text
server/briefing.env.example.ps1 -> server/briefing.env.ps1
server/kakao-recipients.example.json -> server/kakao-recipients.json
```

Then register the scheduled task from an elevated PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\setup_scheduler.ps1
```

## When `npm` Is Not Recognized

If PowerShell prints `npm : The term 'npm' is not recognized as the name of a cmdlet, function, script file, or operable program`, Node.js/npm is not installed or is not on PATH.

If you only need the local server, start the server script directly without npm:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080
```

You can also use the batch file:

```powershell
server\start_server.bat
```

To keep using `npm run dev:local`, install Node.js LTS, open a new PowerShell window, and verify npm:

```powershell
winget install OpenJS.NodeJS.LTS
node -v
npm -v
npm run dev:local
```

## Tests

Run structure and PostgreSQL backup dry-run checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Run Playwright E2E after installing Node dependencies and browser binaries. E2E can use `?storage=test` or the Playwright flag for browser mock storage.

```powershell
npm install
npx playwright install chromium
npm run test:e2e
```
