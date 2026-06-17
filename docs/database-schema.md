# Database Schema

## Current Store

ForHome uses PostgreSQL as the production and persistent data store. The schema lives in `server/sql/schema.sql`, and `server/db.ps1` applies it during server-side database initialization.

The frontend still exchanges an app-state shaped JSON object through `GET /api/state` and `PUT /api/state`, but the server reads and writes normalized PostgreSQL tables.

## Core Tables

### Accounts And Households

| Table | Purpose |
| --- | --- |
| `users` | Login account, password hash, display name, admin flag, activity status |
| `households` | A home/family group owned by an initial representative hero |
| `household_members` | A user's membership/profile/role inside a household |
| `settings` | Household-level settings such as vacation threshold and week start |

Roles:

| Role | Display Meaning |
| --- | --- |
| `owner` | Representative hero who created the household |
| `hero` | Home hero who can do chores/care work |
| `care_member` | Member who is cared for or receives support |

### Auth And Invitations

| Table | Purpose |
| --- | --- |
| `sessions` | Server-issued login sessions; stores `token_hash`, not raw token |
| `invitations` | Invite token/code hashes, role hint, expiry, use count |

Password hash format:

```text
pbkdf2_sha256$iterations$salt$hash
```

### Chores And Approval

| Table | Purpose |
| --- | --- |
| `chores` | Household chore master data |
| `task_entries` | Completed chore records and proof/review metadata |
| `task_approvals` | Reviewer-by-reviewer approval status |
| `task_point_recipients` | Members who receive points for an entry |

### Care

| Table | Purpose |
| --- | --- |
| `care_items` | Care activity master data |
| `care_assignments` | Date-level morning/evening care assignment |
| `care_sessions` | Timed care session records |
| `care_session_point_recipients` | Members who receive points for a care session |

### Plans, Messages, Badges, Requests

| Table | Purpose |
| --- | --- |
| `tomorrow_plans` | Tomorrow/date-based chore requests |
| `messages` | Household messages |
| `badge_history` | Badge event history |
| `member_badges` | Current badge ownership by member |
| `change_requests` | Pending or applied setting/member/chore change requests |
| `change_request_approvals` | Reviewer approval state for change requests |
| `app_version` | Monotonic state version and update timestamp |

## Compatibility State Object

The browser receives this shape for compatibility with the existing UI:

```text
{
  version,
  updatedAt,
  settings,
  members,
  accounts,
  chores,
  history,
  tomorrowPlans,
  messages,
  badgeHistory,
  careAssignments,
  careSessions,
  careItems,
  changeRequests
}
```

`Set-DbState` maps the state object back into normalized tables. This keeps the migration bounded while allowing future APIs to become table-specific CRUD routes.

## Backup

`scripts/postgresql-backup.ps1` reads the state through `Get-DbState` and writes:

```text
data/backups/YYYY-MM-DD/state.json
reports/daily/YYYY-MM-DD.md
```

It also supports fixture dry-runs so tests can run without a live PostgreSQL instance.
