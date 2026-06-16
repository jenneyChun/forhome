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

## Agent Roles

### Frontend Agent

- Role: inspect `code/index.html` UI surfaces and recommend minimal screen changes.
- Scope: settings screen, review screen, calendar/care screen, and family member display.
- Output used:
  - Add adult/child role selection to family settings.
  - Add care item management to settings.
  - Add item change approval queue to the review screen.
  - Add care item and child participant controls to the care time form.
  - Keep changes inside existing tabs instead of creating new screens.

### Backend Agent

- Role: inspect state model, persistence normalization, and backup/report impact.
- Scope: `code/index.html` state functions and `scripts/firestore-backup.js`.
- Output used:
  - Add `members[].role`.
  - Add `careItems[]`.
  - Add `changeRequests[]`.
  - Replace parent-id checks with adult-role helpers.
  - Route item changes through approval requests.
  - Add multi-recipient point handling for education care records.
  - Extend backup reports and morning briefing with item change/care point data.

### QA Agent Brief

- Role: preserve verification knowledge for future QA agent runs.
- Scope: P0 flows, approval rules, item change approval, care education points, and backup/report checks.
- Output created:
  - `docs/agents/qa-brief.md`

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

## Agent Brief Documents

- Added `docs/agents/frontend-brief.md`.
  - Captures frontend responsibilities, key render functions, UI model, and edit rules.
- Added `docs/agents/backend-brief.md`.
  - Captures state model, normalization rules, change request model, care points, and backup/report responsibilities.
- Added `docs/agents/qa-brief.md`.
  - Captures regression checklist, high-risk flows, and verification commands.

These brief documents are intended to reduce repeated code analysis by future subagents.

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

## Commit: 568e3fa docs: add agent briefs

This commit documents the agent operating model created after the role/item approval/care points implementation.

- Added Frontend agent brief for UI responsibilities, key render functions, and minimal-edit rules.
- Added Backend agent brief for shared state, normalization, approval request, care point, and backup/report rules.
- Added QA agent brief for P0 regression checks, high-risk flows, and verification commands.
- Updated this session note with each agent role and the implementation decisions that came from their analysis.
- Purpose: reduce repeated full-code analysis by future subagents and make future work start from stable project memory in `docs/agents`.
