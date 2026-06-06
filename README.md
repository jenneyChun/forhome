# ForHome

ForHome is a family chore web app deployed as a static Firebase Hosting app. Firebase Auth signs family members in, Cloud Firestore stores shared app data, and GitHub Actions writes dated JSON/Markdown backups.

## Folder Layout

- `code/`: browser client code served by Firebase Hosting
- `server/`: local PowerShell static server for Playwright and LAN smoke checks
- `scripts/`: automation scripts such as Firestore backup export
- `data/`: generated exports and backup output
- `log/`: local runtime logs and Playwright reports
- `tests/`: structure tests, fixtures, and Playwright E2E tests
- `docs/`: requirements and Codex session notes

## Firebase Setup

The default Firebase project is `forhome-19317`.

Create these Firebase Auth email/password users:

```text
admin@forhome.local / admin1234
mom@forhome.local / mom1234
dad@forhome.local / dad1234
son@forhome.local / son1234
```

Deploy Firestore rules and hosting with the Firebase CLI:

```powershell
firebase deploy --only firestore:rules,hosting
```

The first admin login seeds the shared Firestore document:

```text
families/forhome/state/app
```

## GitHub Backup

The workflow `.github/workflows/firestore-backup.yml` runs daily at `15:10 UTC`, which is `00:10 KST`, and writes:

```text
data/backups/YYYY-MM-DD/state.json
reports/daily/YYYY-MM-DD.md
```

Add this repository secret before enabling the workflow:

```text
FIREBASE_SERVICE_ACCOUNT_JSON
```

The value must be a Firebase service account JSON with permission to read Firestore.

## Morning Briefing

The local Windows scheduler can send the 07:00 KST ForHome briefing to mom and dad through Kakao memo-to-me.

Copy and fill these local-only files:

```text
server/briefing.env.example.ps1 -> server/briefing.env.ps1
server/kakao-recipients.example.json -> server/kakao-recipients.json
```

Then register the scheduled task from an elevated PowerShell window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\setup_scheduler.ps1
```

## Local Test Server

For local development and Playwright checks, run:

```bash
npm run dev:local
```

Then open:

- PC: `http://localhost:8080`
- Mobile: use the LAN URL printed by the server window

Localhost automatically uses a browser localStorage mock and does not call Firebase. You can also force modes explicitly:

```text
http://localhost:8080/?storage=test
http://localhost:8080/?storage=firebase
```

`npm run dev` is an alias for the same local server.

If Node/npm is not installed, the same server can still be started directly:

```powershell
server\start_server.bat
```

## Tests

Run structure and dry-run backup checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Run Playwright E2E after installing Node dependencies and browser binaries:

```powershell
npm install
npx playwright install chromium
npm run test:e2e
```
