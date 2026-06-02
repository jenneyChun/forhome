# 2026-06-03 PostgreSQL Folder Refactor

## User Request

1. Replace JSON data storage with PostgreSQL.
2. Separate code from folders that hold runtime user data.
3. Organize folders by role.
4. Create `docs` and `docs/session` for future guides and Codex implementation notes.
5. Use role folders such as `code`, `log`, `tests`, `server`, and `data`.
6. Always create verification test cases for implemented changes.
7. Push completed implementation to GitHub.

## Implementation Notes

- Moved browser client code to `code/index.html`.
- Moved server scripts to `server/`.
- Added PostgreSQL schema at `server/sql/schema.sql`.
- Added PostgreSQL access layer at `server/db.ps1`.
- Changed server API to read/write PostgreSQL state through `Get-DbState` and `Set-DbState`.
- Separated runtime config and generated exports under `data/`.
- Separated runtime logs under `log/`.
- Moved Playwright config and E2E tests under `tests/`.
- Added PowerShell verification test runner at `tests/run-tests.ps1`.
- Added the requirements document under `docs`.

## Verification Plan

- Run `tests/run-tests.ps1` for folder structure, file existence, PowerShell parsing, and PostgreSQL-oriented server checks.
- After PostgreSQL and `psql` are installed, set `RUN_DB_TESTS=1` and re-run `tests/run-tests.ps1`.
- After Node/npm/Playwright are installed, run `npm run test:e2e`.

## Environment Note

At implementation time, `psql`, Docker, Node, and npm were not available on PATH, so live PostgreSQL and Playwright checks are prepared but not fully executable in this environment.

## Verification Result

- `tests/run-tests.ps1` passed.
- Direct server start currently fails with a clear missing `psql` message, which is expected until PostgreSQL client tools are installed.
- Non-ASCII content was removed from source file bodies to avoid Windows PowerShell encoding drift. User-entered display names and chore names are stored in PostgreSQL.
