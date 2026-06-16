# Architecture

## 전체 구조

ForHome은 정적 프론트엔드 중심 구조다. 운영 환경에서는 Firebase Hosting이 `code/index.html`을 제공하고, 브라우저 앱이 Firebase Auth와 Cloud Firestore에 직접 연결한다. 로컬 환경에서는 PowerShell 정적 서버가 HTML 파일을 제공하며, `localhost`에서는 기본적으로 Firebase 대신 `localStorage` mock 저장소를 사용한다.

```text
Browser
  -> Firebase Hosting / local PowerShell static server
  -> Firebase Auth
  -> Cloud Firestore families/forhome/state/app

GitHub Actions
  -> scripts/firestore-backup.js
  -> Firestore Admin SDK
  -> data/backups/YYYY-MM-DD/state.json
  -> reports/daily/YYYY-MM-DD.md

Windows Task Scheduler
  -> server/send_kakao.ps1
  -> scripts/firestore-backup.js --briefing
  -> Kakao memo-to-me API
```

## 프론트엔드

### 코드에서 확인된 내용

- 위치: `code/index.html`
- HTML, CSS, JavaScript가 하나의 파일에 들어 있다.
- 별도 번들러, React, Vue 같은 프론트엔드 프레임워크는 사용하지 않는다.
- 화면은 로그인 화면과 앱 화면으로 나뉜다.
- 앱 화면은 `home`, `tasks`, `badges`, `calendar`, `settings` 탭으로 구성된다.
- Firebase SDK는 CDN에서 동적으로 로드한다.
- `?storage=test` 또는 `localhost`에서는 test storage provider를 사용한다.
- `?storage=firebase`에서는 Firebase storage provider를 강제할 수 있다.

### 추정한 내용

- MVP 수준에서는 단일 파일 구조가 빠르지만, 기능이 늘어나면 상태 관리, 렌더링, 데이터 접근 코드를 모듈로 분리해야 유지보수가 쉬워진다.

## 백엔드

### 코드에서 확인된 내용

- 운영 애플리케이션 API 서버는 없다.
- `server/server.ps1`은 정적 파일 제공과 `/api/health`만 처리한다.
- `/api/*` 요청 대부분은 `410 api_removed`로 응답한다.
- production storage는 Firebase Firestore라고 명시되어 있다.
- `server/db.ps1`과 `server/sql/schema.sql`은 존재하지만 현재 운영 데이터 경로에서는 사용되지 않는다.

### 추정한 내용

- 과거 PostgreSQL 기반 로컬 서버 구조가 있었고, 이후 Firebase 중심 구조로 전환된 흔적이 있다.

## 데이터베이스

### 코드에서 확인된 내용

- 현재 주 저장소는 Cloud Firestore다.
- 메인 상태 문서는 `families/forhome/state/app`이다.
- 앱 상태 대부분은 단일 문서 안의 배열 필드로 저장된다.
- 문서 필드는 `members`, `accounts`, `chores`, `history`, `tomorrowPlans`, `messages`, `badgeHistory`, `careAssignments`, `careSessions`, `settings`, `version`, `updatedAt`이다.
- 로컬 테스트 모드에서는 같은 상태 구조를 `localStorage` 키 `forhome-test-state-v1`에 저장한다.

## 외부 API

### Firebase

- Firebase Hosting: 정적 파일 배포
- Firebase Auth: 운영 로그인
- Cloud Firestore: 공유 앱 상태 저장
- Firebase Admin SDK: GitHub Actions 백업 스크립트에서 Firestore 읽기

### GitHub Actions

- Firestore 상태를 매일 백업한다.
- 백업 결과를 저장소에 커밋한다.
- 필요한 secret은 `FIREBASE_SERVICE_ACCOUNT_JSON`이다.

### Kakao API

- `server/send_kakao.ps1`은 Kakao OAuth refresh token으로 access token을 갱신한다.
- Kakao memo-to-me API로 아침 브리핑 메시지를 보낸다.
- `server/send_codex_update.ps1`은 GitHub/Codex 업데이트 알림도 Kakao로 보낼 수 있다.

## 배포 및 실행

### 코드에서 확인된 내용

- 로컬 실행: `npm run dev` 또는 `npm run dev:local`
- 직접 실행: `server/start_server.bat`
- Firebase 배포: `firebase deploy --only firestore:rules,hosting`
- 구조 테스트: `npm test`
- E2E 테스트: `npm run test:e2e`

