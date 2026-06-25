# Current Features

## Login And Session

- Login is handled by `POST /api/auth/login`.
- Accounts are stored in PostgreSQL `users`.
- Passwords are stored as PBKDF2-SHA256 hashes.
- The server issues an `httpOnly` `forhome_session` cookie.
- PostgreSQL stores only the session token hash in `sessions`.
- `GET /api/session` restores the browser session after reload.

Default local accounts:

```text
admin / admin1234
mom / mom1234
dad / dad1234
son / son1234
```

## Household Signup And Invitations

- `POST /api/auth/register-owner` creates a first account, household, and owner membership.
- `POST /api/invites` creates an invitation for the current household.
- `GET /api/invites/:id` previews an invitation.
- `POST /api/invites/:id` accepts an invitation and creates the invited account/member.
- Invite URL tokens and short codes are returned once to the creator/acceptor flow; PostgreSQL stores only hashes.

Roles:

| Role | Display |
| --- | --- |
| `owner` | Representative hero |
| `hero` | Home hero |
| `care_member` | Care member |

## App Data

The UI still works through a single compatible app-state object, but server-side persistence is normalized in PostgreSQL.

Current state areas:

- household settings
- members and account mapping
- chores
- task history
- approval requests
- proof captions/images
- tomorrow plans
- care assignments
- care sessions
- messages
- badge history
- change requests

## Web and Mobile Clients

- Web shell: `code/web/` at `http://localhost:8080`
- Mobile shell: `code/mobile/` at `http://m.localhost:8080`
- Shared logic: `code/shared/forhome-core.js`
- Playwright/local UI checks can use `?storage=test` for browser mock storage.

## Backup And Briefing

- `scripts/postgresql-backup.ps1` writes dated JSON and Markdown reports.
- `.github/workflows/postgresql-backup.yml` runs the PostgreSQL backup on a daily schedule.
- `server/send_kakao.ps1` uses the PostgreSQL backup script's briefing output.

## Tests

- `tests/run-tests.ps1` checks the PostgreSQL server/API structure, schema, docs, and fixture backup output.
- Playwright E2E keeps using mock browser storage so UI flows can run without a live DB.
