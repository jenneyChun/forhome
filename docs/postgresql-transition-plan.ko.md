# PostgreSQL 전환 계획

## 요약

ForHome의 운영/영구 저장소를 PostgreSQL로 전환했다. 브라우저는 PostgreSQL에 직접 연결하지 않고 `server/server.ps1` API만 호출한다. 인증은 PostgreSQL `users` 테이블과 서버 발급 `httpOnly` 세션 쿠키를 사용한다.

Firebase Auth, Firestore 직접 접근, Firestore 백업 워크플로는 운영 경로에서 제거했다. Playwright와 로컬 UI 확인을 위한 `localStorage` mock provider는 `?storage=test` 또는 테스트 플래그에서만 유지한다.

## 구현된 변경점

### 서버

- `server/server.ps1`을 정적 서버 + API 서버로 확장했다.
- `/api/health`는 PostgreSQL 연결 상태를 반환한다.
- 로그인 성공 시 `forhome_session` 쿠키를 `HttpOnly`, `SameSite=Lax`, `Max-Age=2592000` 속성으로 발급한다.
- 세션 원본 토큰은 브라우저 쿠키에만 두고, DB에는 SHA-256 hash를 저장한다.

구현된 API:

```text
POST /api/auth/register-owner
POST /api/auth/login
POST /api/auth/logout
GET  /api/session
GET  /api/state
PUT  /api/state
POST /api/invites
GET  /api/invites/:id
POST /api/invites/:id
```

### 데이터베이스

- `server/db.ps1`은 PostgreSQL 연결, 스키마 적용, 인증, 세션, 초대, 앱 상태 읽기/쓰기를 담당한다.
- `server/sql/schema.sql`은 단일 JSONB 상태 저장이 아니라 정규화 테이블을 기본 모델로 사용한다.
- 기본 로컬 계정은 서버 초기화 시 준비된다.

핵심 테이블:

```text
users
households
household_members
sessions
invitations
chores
task_entries
task_approvals
task_point_recipients
care_items
care_assignments
care_sessions
care_session_point_recipients
tomorrow_plans
messages
badge_history
member_badges
settings
change_requests
change_request_approvals
```

비밀번호 저장 형식:

```text
pbkdf2_sha256$iterations$salt$hash
```

### 프론트엔드

- `code/index.html`의 운영 저장소 provider를 `createPostgresApiProvider()`로 교체했다.
- Firebase SDK 로딩, `firebase.initializeApp`, Firestore 문서 경로 접근을 제거했다.
- `GET /api/session`, `POST /api/auth/login`, `GET /api/state`, `PUT /api/state`를 사용한다.
- `owner`, `hero`, `care_member` 역할을 기존 화면 로직의 성인/아이 권한과 호환되게 매핑한다.
- `createTestStorageProvider()`는 Playwright/로컬 UI 테스트 전용으로 유지한다.

### 가입과 초대

- 최초 가입자는 `owner`로 household를 생성한다.
- 초대 생성 시 서버가 URL token과 short code를 만들고, PostgreSQL에는 hash만 저장한다.
- 초대 수락 시 `hero` 또는 `care_member` 역할로 `household_members` 멤버십을 생성한다.
- 초대 공유용 응답에는 web URL, mobile URL, QR payload, short code가 포함된다.

추천 표시명:

| 내부 역할 | 표시명 | 의미 |
| --- | --- | --- |
| `owner` | 대표 히어로 | 집을 처음 만들고 초대/관리 권한을 가진 사람 |
| `hero` | 홈 히어로 | 집안일과 돌봄을 수행하는 구성원 |
| `care_member` | 케어 멤버 | 돌봄이나 지원을 받는 구성원 |

### 백업과 브리핑

- `.github/workflows/firestore-backup.yml`을 제거하고 `.github/workflows/postgresql-backup.yml`을 추가했다.
- `scripts/firestore-backup.js`를 제거하고 `scripts/postgresql-backup.ps1`을 추가했다.
- `server/send_kakao.ps1`은 새 PostgreSQL 백업 스크립트의 briefing 출력을 사용한다.
- GitHub Actions는 `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` secrets를 사용한다.

## 실행 방법

로컬 서버:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080
```

PostgreSQL 연결 설정:

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your-password"
```

백업 dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\postgresql-backup.ps1 -Fixture tests\fixtures\backup-state.json -Date 2026-06-03 -OutDir log\backup-dry-run
```

## 검증

현재 구조 테스트는 다음을 확인한다.

- PowerShell 스크립트 파싱
- PostgreSQL API 라우트 존재
- PBKDF2 비밀번호 hash와 세션 token hash 사용
- 핵심 PostgreSQL 테이블 정의
- 프론트엔드가 Firebase SDK 대신 PostgreSQL API provider 사용
- Firestore 백업 스크립트/워크플로 제거
- PostgreSQL 백업 fixture dry-run
- Kakao briefing이 PostgreSQL 백업 스크립트 사용

실행:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

실제 PostgreSQL 연결 테스트는 `psql`과 DB가 준비된 환경에서 아래처럼 확장 실행한다.

```powershell
$env:RUN_DB_TESTS = "1"
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

## 남은 작업

- `server/server.ps1`의 단순 PowerShell HTTP 서버는 MVP용이다. 운영 배포 전에는 리버스 프록시, TLS, rate limit, request size limit을 추가해야 한다.
- 초대 수락 전용 UI와 QR 이미지 렌더링은 API 기반만 준비되어 있으며 화면 연결이 필요하다.
- `GET /api/state`와 `PUT /api/state`는 기존 단일 상태 객체 호환을 위해 유지한다. 화면별 CRUD API는 다음 단계에서 점진적으로 분리한다.
- 사진 증빙은 현재 상태 문자열 호환을 유지한다. 운영에서는 별도 object storage 또는 파일 저장소로 분리하는 것이 좋다.
