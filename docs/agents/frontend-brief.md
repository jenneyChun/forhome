# Frontend Agent Brief

## 목적

이 문서는 Frontend agent가 ForHome 코드를 수정할 때 반복 분석을 줄이기 위한 기준 문서다.

Frontend agent는 먼저 이 문서와 `docs/user-flow.md`를 확인하고, 필요한 함수 주변만 읽는다. 전체 코드 재분석은 피한다.

## 제품 방향

ForHome은 집안일을 공유하는 가족 내부 SNS다.

핵심 흐름:

```text
기록 -> 증빙 -> 확인 -> 피드/요약 -> 인정 -> 협업
```

## 주요 파일

- `code/index.html`
  - 현재 프론트엔드, 상태 관리, Firebase/localStorage 저장 로직이 모두 들어 있는 단일 HTML 앱이다.
- `docs/user-flow.md`
  - 화면 흐름과 사용자 동작의 기준 문서다.
- `docs/pm-requirements.md`
  - 기능 우선순위와 요구사항의 기준 문서다.

## 주요 화면 함수

- `renderHome()`
  - 오늘 화면, 가족 피드, 확인 대기, 오늘 해야 할 일을 렌더링한다.
- `renderTasks()`
  - 집안일 기록 화면을 렌더링한다.
- `renderCalendar()`
  - 내일 할 일, 육아 담당, 육아 시간 기록 화면을 렌더링한다.
- `renderBadges()`
  - 확인/리뷰 화면을 렌더링한다.
  - 현재 집안일 확인 큐와 설정 변경 승인 큐를 함께 보여준다.
- `renderSettings()`
  - 관리자 설정 화면을 렌더링한다.
  - 가족 구성원, 집안일, 육아 항목, 계정을 관리한다.

## 현재 UI 모델

### 가족 구성원

- 구성원은 `adult` 또는 `child` 역할을 가진다.
- 설정 화면에서 구성원 이름과 권한을 추가한다.
- 화면 표시는 `성인 권한`, `아이 권한`으로 한다.

관련 함수:

- `memberRole(m)`
- `adultMembers()`
- `childMembers()`
- `renderMemberSetting(m)`
- `renderMemberSelect(m)`
- `addMember()`

### 집안일 항목

- 집안일 항목은 `state.chores`에 저장된다.
- 항목별 포인트는 `fatigue`, XP는 `xp`로 저장된다.
- 집안일 추가/삭제는 즉시 반영하지 않고 설정 변경 승인 요청으로 생성한다.

관련 함수:

- `addChore()`
- `removeChore(id)`
- `renderChoreSetting(c)`
- `createChangeRequest(type, before, after)`

### 육아 항목

- 육아 항목은 `state.careItems`에 저장된다.
- 기본 항목으로 `edu`가 있다.
- 화면에서는 `교육 기본 포함`으로 안내한다.
- 육아 항목 추가/삭제도 설정 변경 승인 요청으로 생성한다.

관련 함수:

- `addCareItem()`
- `removeCareItem(id)`
- `renderCareItemSetting(item)`
- `careItemOptions(selected)`

### 설정 변경 승인

- 설정 변경 요청은 `state.changeRequests`에 저장된다.
- 리뷰 화면의 `설정 변경 승인` 영역에서 승인/반려한다.

관련 함수:

- `renderChangeRequestItem(request)`
- `approveChangeRequest(id)`
- `rejectChangeRequest(id)`
- `pendingChangeRequests()`

### 육아 기록과 교육 포인트

- 육아 시간 기록 화면은 성인 담당자, 아이, 육아 항목을 선택한다.
- `교육` 항목을 선택하면 성인과 아이가 모두 포인트를 받는다.
- 포인트 수신자는 `pointRecipients`에 저장된다.

관련 함수:

- `renderCalendar()`
- `addCareSession()`
- `renderCareSession(item)`

## 수정 시 주의사항

- 새 화면을 만들기보다 기존 탭 안에서 확장한다.
- `PARENT_IDS` 직접 의존을 늘리지 않는다. 성인/아이 역할 helper를 사용한다.
- 사용자가 보는 용어는 `부담`보다 `포인트`, `수고 포인트`를 우선한다.
- 집안일/육아 항목 변경은 즉시 저장하지 말고 설정 변경 승인 요청으로 보낸다.
- 문구 변경은 `docs/user-flow.md`와 어긋나지 않게 한다.

## 권장 작업 방식

1. `docs/user-flow.md`에서 해당 흐름만 확인한다.
2. 이 문서에서 관련 함수명을 찾는다.
3. `code/index.html`에서 해당 함수 주변만 읽는다.
4. 작은 패치로 수정한다.
5. `node --check`와 `npm.cmd test`를 실행한다.
