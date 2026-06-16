# Roadmap

## 목표

ForHome을 가족 내부에서 안정적으로 쓸 수 있는 MVP로 발전시키려면, 현재 작동하는 단일 문서/단일 파일 구조를 유지 가능한 구조로 나누고, 보안 경계를 Firebase rules 또는 서버 측 로직으로 옮기는 작업이 우선이다.

## 1단계: 현재 MVP 안정화

### 코드에서 확인된 기반

- 주요 사용자 흐름은 이미 구현되어 있다.
- 로컬 mock 저장소와 Playwright E2E 테스트가 있다.
- Firebase Hosting, Firestore rules, GitHub Actions 백업이 있다.

### 다음 작업

- Firebase Auth 사용자 생성 절차를 문서화하거나 스크립트화한다.
- 실제 배포 URL, Firebase Console 설정, GitHub secret 설정 체크리스트를 만든다.
- 기본 계정과 앱 내부 계정의 관계를 명확히 정리한다.
- `docs`에 운영 runbook을 추가한다.
- Kakao 브리핑 dry-run과 실제 발송 절차를 분리해 문서화한다.

## 2단계: 데이터 모델 분리

### 다음 작업

- 단일 Firestore 문서에서 주요 배열을 컬렉션으로 분리한다.
- 권장 컬렉션 예시:
  - `families/{familyId}/members/{memberId}`
  - `families/{familyId}/chores/{choreId}`
  - `families/{familyId}/history/{historyId}`
  - `families/{familyId}/tomorrowPlans/{planId}`
  - `families/{familyId}/messages/{messageId}`
  - `families/{familyId}/careAssignments/{date}`
  - `families/{familyId}/careSessions/{sessionId}`
- 사진 증빙은 Firestore 문서가 아니라 Firebase Storage로 옮긴다.
- 날짜, 구성원, 승인 상태 기준 조회 인덱스를 설계한다.

## 3단계: 보안 모델 강화

### 다음 작업

- 앱 내부 평문 비밀번호를 제거한다.
- Firebase Auth UID와 구성원/역할을 Firestore membership 문서로 연결한다.
- Firestore rules에서 역할별 읽기/쓰기 권한을 검증한다.
- 승인 요청 처리 시 검토자가 실제 권한을 가진 사용자인지 rules 또는 Cloud Functions로 검증한다.
- 관리자만 설정, 구성원, 집안일, 계정을 변경할 수 있도록 서버 측 권한을 강제한다.

## 4단계: 프론트엔드 구조 개선

### 다음 작업

- `code/index.html`을 모듈로 분리한다.
- 추천 분리 단위:
  - storage provider
  - auth/session
  - state normalization
  - rendering
  - feature handlers
  - date/time helpers
- HTML 문자열 렌더링을 줄이고 컴포넌트 단위 렌더링 패턴을 만든다.
- 전역 함수 의존을 줄인다.
- 핵심 비즈니스 로직을 순수 함수로 분리해 단위 테스트를 추가한다.

## 5단계: 운영 자동화

### 다음 작업

- Firebase 배포 GitHub Actions를 추가한다.
- Firestore rules 테스트를 추가한다.
- 백업 실패 알림을 추가한다.
- Kakao 브리핑을 로컬 PC가 아니라 GitHub Actions 또는 Cloud Scheduler/Cloud Functions로 옮기는 방안을 검토한다.
- service account 권한을 최소화한다.

## 6단계: 사용자 경험 개선

### 다음 작업

- 모바일에서 사진 첨부와 완료 기록 흐름을 더 짧게 만든다.
- 승인 대기 알림을 더 명확히 보여준다.
- 오늘 해야 할 일, 내가 요청받은 일, 내가 승인해야 할 일을 첫 화면에서 분리한다.
- 반려된 작업의 재제출 흐름을 만든다.
- 장기 기록을 월별/주별로 필터링한다.

## 7단계: 확장 가능한 제품화

### 다음 작업

- 가족 단위 `familyId`를 고정값 `forhome`에서 동적으로 확장한다.
- 초대 링크 또는 초대 코드 기반 가족 가입을 구현한다.
- 가족별 역할을 `admin`, `parent`, `child`, `viewer` 등으로 명확히 정의한다.
- 다국어 또는 한국어 UI 정리를 진행한다.
- 접근성, 키보드 조작, 오류 상태 UX를 개선한다.

## 우선순위 제안

1. 운영 배포/계정/secret 문서화
2. 평문 비밀번호 제거 및 membership 기반 권한 전환
3. 사진 증빙을 Firebase Storage로 이동
4. `history`, `messages`, `tomorrowPlans` 컬렉션 분리
5. `index.html` 모듈화
6. Firestore rules 테스트와 E2E 확대

