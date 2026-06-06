# Codex 카카오톡 알림

Codex가 구현한 내용을 GitHub에 push하면 `.github/workflows/codex-kakao-notify.yml` 워크플로가 실행되고, 최신 커밋 주소를 카카오톡으로 보냅니다.

## GitHub Secrets

GitHub 저장소의 `Settings > Secrets and variables > Actions > Repository secrets`에 아래 값을 등록합니다.

```text
KAKAO_RECIPIENTS_JSON
KAKAO_REST_API_KEY
KAKAO_CLIENT_SECRET
```

`KAKAO_CLIENT_SECRET`은 카카오 앱에서 client secret을 사용하지 않으면 비워둘 수 있습니다. `KAKAO_REST_API_KEY`를 각 수신자 JSON 안에 넣는 경우에도 Repository secret으로 둘 수 있습니다.

`KAKAO_RECIPIENTS_JSON` 예시는 다음과 같습니다.

```json
[
  {
    "id": "mom",
    "label": "Mom",
    "refreshToken": "KAKAO_REFRESH_TOKEN_FOR_MOM"
  },
  {
    "id": "dad",
    "label": "Dad",
    "refreshToken": "KAKAO_REFRESH_TOKEN_FOR_DAD"
  }
]
```

각 수신자마다 다른 카카오 앱을 쓰면 `restApiKey`와 `clientSecret`을 수신자 항목 안에 직접 넣을 수 있습니다.

## 로컬 확인

토큰 없이 메시지 내용을 확인합니다.

```powershell
npm run notify:codex:dry-run
```

`server\kakao-recipients.json`과 `server\briefing.env.ps1`을 채운 뒤 실제로 발송합니다.

```powershell
npm run notify:codex
```

## GitHub 반영 알림

아래처럼 commit 후 GitHub에 push하면 Actions가 최신 커밋 URL을 카카오톡으로 보냅니다.

```powershell
git add .
git commit -m "feat: add Codex Kakao notification"
git push origin main
```

카카오톡 메시지에는 다음 정보가 포함됩니다.

```text
ForHome Codex update
Repository: jenneyChun/forhome
Commit: abc1234
Message: feat: add Codex Kakao notification
GitHub: https://github.com/jenneyChun/forhome/commit/...
```

## Codex에 다시 요청하는 명령

현재 카카오 REST 메시지 API는 발송용으로 사용 중이라, 카카오톡 답장을 자동으로 Codex가 읽지는 않습니다. 답장으로 남긴 내용을 Codex에 그대로 붙여넣을 때는 아래 형식을 사용합니다.

```text
Codex 구현: <원하는 수정 내용>
Codex 확인: npm run test:e2e
Codex 배포: firebase deploy --only firestore:rules,hosting
```

예시:

```text
Codex 구현: 엄마/아빠 오늘 할 일을 홈 화면 상단에 더 크게 보여줘
```

카카오톡 답장을 자동으로 Codex 작업으로 연결하려면 KakaoTalk Channel webhook, 공개 HTTPS 엔드포인트, GitHub Actions 또는 별도 서버를 잇는 브리지가 추가로 필요합니다.
