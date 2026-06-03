# 2026-06-03 Firebase Hosting, Firestore, and GitHub Backup

## Goal

Move ForHome's production architecture away from the PC-hosted PostgreSQL server and toward a deployed static app with Firebase shared data.

## Decisions

1. Firebase project: `forhome-19317`.
2. App deployment: Firebase Hosting with `code/` as the public root.
3. Shared DB: Cloud Firestore document `families/forhome/state/app`.
4. Login: Firebase Auth using email-mapped versions of the existing accounts.
5. Backup: GitHub Actions commits dated JSON and Markdown files to the current repository.
6. Local server: static PowerShell test server only.

## Implemented Changes

- Added Firebase SDK initialization and a storage provider abstraction in `code/index.html`.
- Added production Firestore provider and Playwright localStorage mock provider.
- Removed browser dependency on `/api/state` and `/api/daily-summary`.
- Added Firebase Hosting config, project config, and Firestore security rules.
- Added a GitHub Actions workflow for daily KST Firestore backups.
- Added `scripts/firestore-backup.js` with fixture-based dry-run support.
- Updated Playwright tests to use `?storage=test` and added a shared-state tab test.
- Updated structure tests and requirements documentation for the Firebase architecture.

## Setup Notes

Create these Firebase Auth users before production use:

```text
admin@forhome.local / admin1234
mom@forhome.local / mom1234
dad@forhome.local / dad1234
son@forhome.local / son1234
```

Add repository secret `FIREBASE_SERVICE_ACCOUNT_JSON` for the backup workflow.

Deploy with:

```powershell
firebase deploy --only firestore:rules,hosting
```
