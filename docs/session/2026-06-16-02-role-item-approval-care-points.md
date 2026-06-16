# 2026-06-16-02 Role, Item Approval, Care Points

## User Request

- Update implementation based on `docs/pm-requirements.md` and `docs/user-flow.md`.
- Frontend and backend agents should use the user flow to modify code.
- Save the change summary in session notes before commit.

## PM/UX Requirement Changes Applied

- Family members can now be modeled with `adult` or `child` roles.
- Family member management should support additional members beyond mom, dad, and son.
- Chore and care items can be custom-managed with points.
- Care items include a default education item.
- Chore/care item changes should go through family approval before being applied.
- Education care records award points to both the adult and child participants.

## Frontend Changes

- Added role display and role selection for family members.
- Added care item management in settings.
- Added item change approval queue to the review screen.
- Added care item and child participant selection to the care time form.
- Updated care session display to show item, child, recipients, and points.

## Backend/State Changes

- Added `members[].role` normalization with backward compatibility.
- Added `careItems[]` to the shared state.
- Added `changeRequests[]` to persist pending setting changes.
- Changed chore/care item add/delete flows to create approval requests before applying.
- Replaced key parent-only checks with adult-role based helpers.
- Added multi-recipient point handling for care education records.
- Updated weekly/member totals to include approved care point entries.

## Backup/Report Changes

- `scripts/firestore-backup.js` now includes member role, point recipients, care item details, and item change requests in daily summaries.
- Markdown daily reports now include an `Item Change Requests` section.
- Morning briefing now includes pending item change counts.

## Verification

- `node --check` passed for the extracted browser script.
- `node --check scripts/firestore-backup.js` passed.
- `git diff --check` passed.
- `npm.cmd test` passed.

## Commit Summary Draft

`feat: add role-based item approvals and care points`

- Add adult/child member role support.
- Add configurable care items and default education item.
- Route chore/care item changes through approval requests.
- Award education care points to both adult and child participants.
- Extend backup reports for item change and care point data.
