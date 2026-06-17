# Architecture

## Current Shape

ForHome now uses a PostgreSQL-backed API server.

```text
Browser
  -> server/server.ps1
     -> static files from code/
     -> /api/* JSON routes
     -> server/db.ps1
     -> PostgreSQL
```

The browser does not connect to PostgreSQL directly. It uses `fetch()` with same-origin credentials and the server owns authentication, authorization, and database access.

## Runtime Pieces

### Browser Client

- Main file: `code/index.html`
- Production storage provider: `createPostgresApiProvider()`
- Test storage provider: `createTestStorageProvider()`
- Mobile layout: enabled by `m.` host or local `?surface=mobile`
- Test mode: enabled by `?storage=test` or `window.__FORHOME_TEST__`

### PowerShell Server

- File: `server/server.ps1`
- Serves static files from `code/`
- Exposes `/api/health`
- Exposes auth/session/invitation/state routes
- Issues `httpOnly` session cookies

### Database Layer

- File: `server/db.ps1`
- Schema: `server/sql/schema.sql`
- Connection config: `data/db.env.ps1` or `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`
- Applies schema and default seed data on demand
- Stores password hashes as `pbkdf2_sha256$iterations$salt$hash`
- Stores only session token hashes

### Backup And Briefing

- Backup script: `scripts/postgresql-backup.ps1`
- GitHub workflow: `.github/workflows/postgresql-backup.yml`
- Kakao briefing: `server/send_kakao.ps1` calls the PostgreSQL backup script with `-Briefing`

## API Boundary

Implemented routes:

```text
POST /api/auth/register-owner
POST /api/auth/login
POST /api/auth/logout
GET  /api/session
GET  /api/state
PUT  /api/state
POST /api/invites
GET  /api/invites/:id
POST /api/invites/:id
GET  /api/health
```

`GET /api/state` and `PUT /api/state` preserve the existing single-state frontend contract while the database stores the data in normalized tables. Screen-level CRUD routes can be split out later without blocking the PostgreSQL migration.

## Data Ownership

PostgreSQL is the source of truth for:

- accounts and login profile data
- households
- household members and roles
- sessions
- invitations
- chores and task entries
- approvals
- care items, assignments, and sessions
- tomorrow plans
- messages
- badges
- settings

## Operational Notes

- Local development can start with `powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080`.
- The server can still serve static files when PostgreSQL is unavailable, but API routes that require DB work will fail until `psql` and connection settings are ready.
- `tests/run-tests.ps1` validates structure and fixture-based backups without requiring a live DB.
- Set `RUN_DB_TESTS=1` to include live PostgreSQL health checks.
