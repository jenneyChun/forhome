# Copy this file to server\briefing.env.ps1 and fill local-only secrets.
$env:FIREBASE_PROJECT_ID = "forhome-19317"
$env:FIRESTORE_FAMILY_ID = "forhome"
$env:FORHOME_APP_URL = "http://localhost:8080"

# Option A: paste the full Firebase service account JSON on one line.
$env:FIREBASE_SERVICE_ACCOUNT_JSON = '{"type":"service_account","project_id":"forhome-19317"}'

# Option B for local dry-runs: point to a fixture instead of Firestore.
# $env:FIRESTORE_BRIEFING_FIXTURE = "C:\path\to\backup-state.json"

# Optional defaults shared by recipients that do not set these values directly.
# $env:KAKAO_REST_API_KEY = ""
# $env:KAKAO_CLIENT_SECRET = ""
