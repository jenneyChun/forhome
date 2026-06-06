# ForHome

ForHome은 Firebase Hosting 정적 앱으로 배포되는 가족 집안일 관리 웹 앱입니다. Firebase Auth로 가족 구성원이 로그인하고, Cloud Firestore에 공유 앱 데이터를 저장하며, GitHub Actions가 날짜별 JSON/Markdown 백업을 생성합니다.

## 폴더 구조

- `code/`: Firebase Hosting에서 제공하는 브라우저 클라이언트 코드
- `server/`: Playwright와 LAN 스모크 체크를 위한 로컬 PowerShell 정적 서버
- `scripts/`: Firestore 백업 내보내기 같은 자동화 스크립트
- `data/`: 생성된 내보내기 파일과 백업 결과
- `log/`: 로컬 런타임 로그와 Playwright 리포트
- `tests/`: 구조 테스트, 픽스처, Playwright E2E 테스트
- `docs/`: 요구사항과 Codex 세션 노트

## Firebase 설정

기본 Firebase 프로젝트는 `forhome-19317`입니다.

다음 Firebase Auth 이메일/비밀번호 사용자를 생성하세요.

```text
admin@forhome.local / admin1234
mom@forhome.local / mom1234
dad@forhome.local / dad1234
son@forhome.local / son1234
```

Firebase CLI로 Firestore 규칙과 Hosting을 배포합니다.

```powershell
firebase deploy --only firestore:rules,hosting
```

첫 번째 관리자 로그인 시 공유 Firestore 문서가 초기화됩니다.

```text
families/forhome/state/app
```

## GitHub 백업

`.github/workflows/firestore-backup.yml` 워크플로는 매일 `15:10 UTC`, 즉 `00:10 KST`에 실행되며 다음 파일을 작성합니다.

```text
data/backups/YYYY-MM-DD/state.json
reports/daily/YYYY-MM-DD.md
```

워크플로를 활성화하기 전에 이 repository secret을 추가하세요.

```text
FIREBASE_SERVICE_ACCOUNT_JSON
```

값은 Firestore 읽기 권한이 있는 Firebase service account JSON이어야 합니다.

## 아침 브리핑

로컬 Windows 스케줄러로 매일 `07:00 KST` ForHome 브리핑을 엄마와 아빠의 Kakao memo-to-me로 보낼 수 있습니다.

아래 예시 파일을 복사한 뒤 로컬 전용 비밀 값을 채우세요.

```text
server/briefing.env.example.ps1 -> server/briefing.env.ps1
server/kakao-recipients.example.json -> server/kakao-recipients.json
```

그다음 관리자 권한 PowerShell에서 예약 작업을 등록합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\setup_scheduler.ps1
```

## 로컬 테스트 서버

로컬 개발과 Playwright 확인을 위해 다음 명령어를 실행하세요.

```bash
npm run dev:local
```

그다음 아래 주소를 여세요.

- PC: `http://localhost:8080`
- 모바일: 서버 창에 출력된 LAN URL 사용

Localhost에서는 브라우저 localStorage mock을 자동으로 사용하며 Firebase를 호출하지 않습니다. 아래처럼 모드를 명시적으로 지정할 수도 있습니다.

```text
http://localhost:8080/?storage=test
http://localhost:8080/?storage=firebase
```

`npm run dev`는 동일한 로컬 서버를 실행하는 별칭입니다.

Node/npm이 설치되어 있지 않아도 같은 서버를 직접 시작할 수 있습니다.

```powershell
server\start_server.bat
```

## 테스트

구조 테스트와 백업 dry-run 체크를 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Node 의존성과 브라우저 바이너리를 설치한 뒤 Playwright E2E를 실행합니다.

```powershell
npm install
npx playwright install chromium
npm run test:e2e
```
