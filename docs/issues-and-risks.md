# Issues And Risks

## 보안 리스크

### 코드에서 확인된 내용

- Firebase API config가 `code/index.html`에 포함되어 있다. Firebase 웹 config 자체는 공개될 수 있지만, 보안은 Firestore rules와 Auth 설정에 의존한다.
- Firestore rules는 `admin@forhome.local`, `mom@forhome.local`, `dad@forhome.local`, `son@forhome.local` 이메일 또는 membership 문서가 있으면 `families/forhome` 전체 하위 문서에 읽기/쓰기를 허용한다.
- 앱 내부 `accounts` 배열에 비밀번호가 평문으로 저장된다.
- 로컬 테스트 모드에서는 평문 비밀번호를 기준으로 로그인한다.
- 사진 증빙은 data URL 문자열로 상태 문서에 저장된다.
- Kakao refresh token은 로컬 `server/kakao-recipients.json` 또는 GitHub secret에 저장되는 구조다.

### 리스크

- Firestore rules가 문서 단위 역할 권한을 강제하지 않아, 허용된 계정은 클라이언트 조작으로 전체 상태를 쓸 수 있다.
- 앱 내부 평문 비밀번호는 운영 권한 판단의 신뢰 근거로 쓰기 어렵다.
- 사진을 Firestore 문서에 직접 저장하면 문서 크기 제한과 개인정보 노출 위험이 커진다.
- `families/forhome/{document=**}` 전체 쓰기 허용은 향후 하위 컬렉션이 늘어날 때 권한 범위가 과도해질 수 있다.

### 추정한 내용

- 현재 가족 내부 신뢰 모델에서는 문제가 덜 드러날 수 있지만, 외부 사용자 초대나 다가구 확장 시 보안 모델을 다시 설계해야 한다.

## 데이터 모델 리스크

### 코드에서 확인된 내용

- 모든 앱 상태가 단일 Firestore 문서에 저장된다.
- `history`, `messages`, `tomorrowPlans`, `careSessions`가 배열로 계속 증가한다.
- 저장 시 전체 상태 문서를 읽고 다시 쓰는 구조다.
- 저장 충돌 시 버전 비교와 재시도성 처리가 일부 있지만, 세밀한 필드 단위 병합은 아니다.

### 리스크

- Firestore 문서 크기 제한에 빨리 도달할 수 있다.
- 여러 사용자가 동시에 기록하면 마지막 저장이 다른 변경을 덮어쓸 가능성이 있다.
- 배열 필드가 커질수록 읽기/쓰기 비용과 렌더링 비용이 증가한다.
- 날짜별 조회, 구성원별 조회, 승인 대기 조회 같은 쿼리를 Firestore에서 효율적으로 수행하기 어렵다.

## 프론트엔드 유지보수 리스크

### 코드에서 확인된 내용

- `code/index.html` 하나에 HTML, CSS, 상태 모델, 저장소, 렌더링, 이벤트 핸들러가 모두 들어 있다.
- DOM 문자열 생성 방식으로 화면을 렌더링한다.
- 전역 변수와 전역 함수가 많다.

### 리스크

- 기능 추가 시 회귀 버그가 생기기 쉽다.
- 화면 단위 테스트와 상태 단위 테스트를 분리하기 어렵다.
- 렌더링 문자열과 데이터 조작이 섞여 있어 권한 검증 누락이 발생하기 쉽다.

## 인증 및 권한 리스크

### 코드에서 확인된 내용

- Firebase Auth 로그인 후에도 앱 내부 계정 배열로 관리자/구성원 매핑을 찾는다.
- settings에서 계정을 추가/삭제할 수 있다.
- 권한 검사는 대부분 클라이언트 로직에 있다.

### 리스크

- 클라이언트 권한 검사는 악의적 사용자를 막는 보안 경계가 아니다.
- 운영에서 관리자 권한, 승인 권한, 구성원 제한은 Firestore rules 또는 서버 함수로 검증해야 한다.

## 운영 리스크

### 코드에서 확인된 내용

- GitHub Actions 백업은 `FIREBASE_SERVICE_ACCOUNT_JSON` secret에 의존한다.
- Kakao 브리핑은 로컬 Windows 작업 스케줄러와 로컬 토큰 파일에 의존할 수 있다.
- Firebase Auth 기본 사용자는 수동 생성이 필요하다.

### 리스크

- 로컬 PC가 꺼져 있으면 Kakao 아침 브리핑이 전송되지 않을 수 있다.
- refresh token 만료 또는 갱신 실패 시 브리핑이 중단된다.
- Firebase Auth 사용자 생성 절차가 자동화되어 있지 않으면 초기 배포 실수가 생길 수 있다.

## 레거시 코드와 혼재

### 코드에서 확인된 내용

- `server/sql/schema.sql`과 `server/db.ps1`이 존재한다.
- 현재 정적 서버는 PostgreSQL을 초기화하지 않는다.
- 테스트도 로컬 서버가 PostgreSQL을 사용하지 않는지 확인한다.

### 리스크

- 새 개발자가 PostgreSQL이 현재 사용 중인지 혼동할 수 있다.
- 레거시 스키마가 최신 Firestore 모델과 달라 문서화 없이 방치되면 잘못된 구현의 근거가 될 수 있다.

## 테스트 리스크

### 코드에서 확인된 내용

- PowerShell 구조 테스트와 Playwright E2E 테스트가 있다.
- E2E는 주요 승인 흐름, 내일 할 일, 육아 시간, 브리핑을 검증한다.

### 리스크

- 단일 HTML 내부 함수에 대한 단위 테스트는 부족하다.
- Firebase 실서비스 rules와 실제 Auth 조합에 대한 통합 테스트는 제한적이다.
- 사진 증빙의 Firestore 크기 문제나 장기 데이터 증가 시나리오 테스트는 없다.

