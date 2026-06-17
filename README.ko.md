# ForHome

ForHome은 가족 구성원이 집안일, 돌봄, 내일 할 일, 메시지를 함께 관리하는 웹 앱입니다. 운영/영구 저장소는 PostgreSQL이며, 브라우저는 DB에 직접 연결하지 않고 `server/server.ps1` API만 호출합니다.

## 폴더 구조

- `code/`: 브라우저 클라이언트 코드
- `server/`: 정적 파일 제공, 인증, 세션, PostgreSQL API를 담당하는 PowerShell 서버
- `server/sql/schema.sql`: PostgreSQL 정규화 스키마
- `scripts/`: PostgreSQL 백업과 자동화 스크립트
- `data/`: 로컬 DB 설정 예시, 내보내기 파일, 백업 결과
- `log/`: 로컬 런타임 로그와 Playwright 리포트
- `tests/`: 구조 테스트, 픽스처, Playwright E2E 테스트
- `docs/`: 요구사항, 설계 문서, Codex 세션 노트

## PostgreSQL 설정

PostgreSQL 서버와 `psql` 클라이언트가 필요합니다. 연결 정보는 환경변수 또는 `data/db.env.ps1`로 주입합니다.

```powershell
$env:PGHOST = "localhost"
$env:PGPORT = "5432"
$env:PGDATABASE = "forhome"
$env:PGUSER = "postgres"
$env:PGPASSWORD = "your-password"
```

`data/db.env.ps1`을 사용할 때도 같은 값을 설정하면 됩니다. 서버 시작 시 `server/db.ps1`이 `server/sql/schema.sql`을 적용하고 기본 데이터/기본 계정을 준비합니다.

기본 로컬 계정:

```text
admin / admin1234
mom / mom1234
dad / dad1234
son / son1234
```

비밀번호는 평문 저장하지 않고 `pbkdf2_sha256$iterations$salt$hash` 형식으로 저장합니다. 로그인 세션은 브라우저에 `httpOnly` 쿠키로 보관하고, DB에는 세션 토큰 hash만 저장합니다.

## 로컬 서버

로컬 개발과 Playwright 확인을 위해 다음 명령어를 실행하세요.

```bash
npm run dev:local
```

Node/npm이 없어도 같은 서버를 직접 시작할 수 있습니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080
```

그다음 아래 주소를 여세요.

- PC: `http://localhost:8080`
- 모바일: 서버 창에 출력된 LAN URL 사용

서버는 정적 파일과 API를 함께 제공합니다.

```text
GET  /api/health
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

## 모바일 레이아웃

모바일 전용 레이아웃은 `m.` 호스트에서 켜집니다. 실제 배포 환경에서는 `https://m.<도메인>`을 같은 API 서버 또는 리버스 프록시에 연결하세요. 모바일 기기가 일반 웹 주소로 들어오면 앱이 `https://m.<현재 도메인>` 주소로 자동 이동합니다.

로컬에서는 별도 `m.` 도메인 대신 쿼리 문자열로 확인할 수 있습니다.

```text
http://localhost:8080/?surface=mobile
http://localhost:8080/?surface=web
```

Playwright나 브라우저 mock 저장소가 필요할 때만 테스트 모드를 명시합니다.

```text
http://localhost:8080/?storage=test
```

## 초대 기반 가입

첫 가입자는 `대표 히어로(owner)`로 집을 만들고, 초대 URL/QR payload/초대 번호를 가족에게 보낼 수 있습니다. 초대받은 사람은 `홈 히어로(hero)` 또는 `케어 멤버(care_member)` 역할로 같은 집에 합류합니다.

자세한 설계는 `docs/auth-invitation-flow.ko.md`와 `docs/postgresql-transition-plan.ko.md`를 참고하세요.

## GitHub 백업

`.github/workflows/postgresql-backup.yml` 워크플로는 매일 `15:10 UTC`, 즉 `00:10 KST`에 실행되며 다음 파일을 작성합니다.

```text
data/backups/YYYY-MM-DD/state.json
reports/daily/YYYY-MM-DD.md
```

워크플로를 활성화하기 전에 repository secrets에 PostgreSQL 연결 정보를 추가하세요.

```text
PGHOST
PGPORT
PGDATABASE
PGUSER
PGPASSWORD
```

로컬 dry-run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\postgresql-backup.ps1 -Fixture tests\fixtures\backup-state.json -Date 2026-06-03 -OutDir log\backup-dry-run
```

## 아침 브리핑

로컬 Windows 스케줄러로 매일 `07:00 KST` ForHome 브리핑을 Kakao memo-to-me로 보낼 수 있습니다.

아래 예시 파일을 복사한 뒤 로컬 전용 비밀 값을 채우세요.

```text
server/briefing.env.example.ps1 -> server/briefing.env.ps1
server/kakao-recipients.example.json -> server/kakao-recipients.json
```

그다음 관리자 권한 PowerShell에서 예약 작업을 등록합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\setup_scheduler.ps1
```

## `npm`이 인식되지 않을 때

PowerShell에서 `npm : 'npm' 용어가 cmdlet, 함수, 스크립트 파일 또는 실행할 수 있는 프로그램 이름으로 인식되지 않습니다.` 오류가 나오면 Node.js/npm이 설치되지 않았거나 PATH에 등록되지 않은 상태입니다.

로컬 서버만 실행하면 되는 경우에는 npm 없이 서버 스크립트를 직접 실행하세요.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File server\server.ps1 -Port 8080
```

또는 배치 파일을 실행해도 됩니다.

```powershell
server\start_server.bat
```

`npm run dev:local` 명령을 계속 사용하려면 Node.js LTS를 설치한 뒤 PowerShell을 새로 열어 확인하세요.

```powershell
winget install OpenJS.NodeJS.LTS
node -v
npm -v
npm run dev:local
```

## 테스트

구조 테스트와 PostgreSQL 백업 dry-run 체크를 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-tests.ps1
```

Node 의존성과 브라우저 바이너리를 설치한 뒤 Playwright E2E를 실행합니다. E2E는 `?storage=test` 또는 Playwright 플래그를 사용해 브라우저 mock 저장소로 검증할 수 있습니다.

```powershell
npm install
npx playwright install chromium
npm run test:e2e
```
