# Backend Agent Brief

## 목적

이 문서는 Backend agent가 ForHome의 상태 모델, 저장, 백업, 리포트 로직을 수정할 때 반복 분석을 줄이기 위한 기준 문서다.

Backend agent는 먼저 이 문서와 `docs/pm-requirements.md`를 확인하고, 필요한 데이터 모델 주변만 읽는다.

## 현재 구조

ForHome은 별도 백엔드 서버 없이 다음 구조로 동작한다.

- 운영 데이터: Firebase Auth + Cloud Firestore
- Firestore 문서: `families/forhome/state/app`
- 로컬 테스트: localStorage mock storage
- 정적 테스트 서버: `server/server.ps1`
- 백업/리포트: `scripts/firestore-backup.js`

상태 모델은 주로 `code/shared/forhome-core.js`의 `defaultState()`와 `normalizeState()`에서 관리한다.

## 주요 파일

- `code/shared/forhome-core.js`
  - 상태 모델, 정규화, 저장, 화면 액션이 모두 들어 있다.
- `scripts/firestore-backup.js`
  - Firestore state를 읽어 날짜별 JSON/Markdown 백업과 아침 브리핑을 만든다.
- `docs/pm-requirements.md`
  - P0/P1 요구사항 기준 문서다.

## 주요 상태 필드

```js
{
  members,
  accounts,
  chores,
  history,
  tomorrowPlans,
  messages,
  careAssignments,
  careSessions,
  careItems,
  changeRequests,
  badgeHistory,
  settings,
  version,
  updatedAt
}
```

## 가족 구성원 모델

`members[]`는 다음 필드를 가진다.

```js
{
  id,
  name,
  emoji,
  restricted,
  role: 'adult' | 'child',
  color,
  xp,
  totalFatigue,
  completedTasks,
  stickers,
  onVacation,
  earnedBadges
}
```

주의:

- 기존 데이터 호환을 위해 `restricted`는 유지한다.
- 새 권한 판단은 `role`을 우선한다.
- 엄마/아빠 고정 판단보다 `adultMembers()`, `childMembers()`, `isAdultMember(id)`를 우선한다.

관련 함수:

- `memberSeed(...)`
- `memberRole(m)`
- `adultMembers()`
- `childMembers()`
- `isAdultMember(id)`
- `normalizeState(next)`

## 집안일 항목 모델

`chores[]`는 기존 구조를 유지한다.

```js
{
  id,
  name,
  emoji,
  fatigue,
  xp,
  category
}
```

해석:

- `fatigue`는 사용자 화면에서 포인트로 표시한다.
- `xp`는 경험치 보상이다.
- 추가/삭제는 바로 적용하지 않고 `changeRequests[]`를 통해 승인 후 적용한다.

## 육아 항목 모델

`careItems[]`는 육아 기록용 항목이다.

```js
{
  id,
  name,
  emoji,
  points,
  xp
}
```

기본 항목:

- `edu`: 교육
- `meal`: 식사 돌봄
- `play`: 놀이 돌봄

주의:

- `edu`는 기본 항목이라 삭제하지 않는다.
- 육아 항목 추가/삭제도 `changeRequests[]`로 승인 후 적용한다.

## 설정 변경 승인 모델

`changeRequests[]`는 집안일/육아 항목 변경 승인에 사용한다.

```js
{
  id,
  type: 'chore.add' | 'chore.delete' | 'care.add' | 'care.delete',
  before,
  after,
  requestedBy,
  requestedAt,
  status: 'pending' | 'approved' | 'rejected',
  reviewedAt,
  reviewNote,
  appliedAt,
  approvalRequests
}
```

관련 함수:

- `createChangeRequest(type, before, after)`
- `requiredChangeReviewers()`
- `changeReviewTargetsFor(request)`
- `syncChangeRequestStatus(request)`
- `applyChangeRequest(request)`
- `approveChangeRequest(id)`
- `rejectChangeRequest(id)`
- `normalizeChangeRequest(request)`

## 완료 기록 모델

집안일 완료 기록은 `history[]`에 저장된다.

중요 필드:

```js
{
  memberId,
  choreId,
  category,
  fatigueAdded,
  xpEarned,
  verificationStatus,
  approvalRequests,
  proofImage,
  proofCaption
}
```

승인된 기록만 포인트/XP 집계에 반영한다.

관련 함수:

- `completeTask()`
- `requiredReviewersFor(memberId, category)`
- `approvalStatusFor(entry)`
- `syncEntryReviewStatus(entry)`
- `approveTask(id)`
- `rejectTask(id)`

## 육아 기록 모델

육아 시간 기록은 `careSessions[]`에 저장된다.

```js
{
  id,
  date,
  memberId,
  childMemberId,
  careItemId,
  pointRecipients,
  points,
  xpEarned,
  startTime,
  endTime,
  minutes,
  note,
  createdAt
}
```

교육 항목 규칙:

- `careItemId === 'edu'`이고 아이가 선택되어 있으면 `pointRecipients`는 `[adultId, childId]`가 된다.
- 그 외 항목은 기본적으로 성인 담당자만 포인트를 받는다.

관련 함수:

- `addCareSession()`
- `normalizeCareSession(item)`
- `carePointEntries()`
- `applyMemberTotals()`
- `weekHistory()`
- `xpFor(m, h)`
- `fatigueFor(m, h)`
- `countFor(m, h)`
- `workRanking(items)`

## 백업/리포트

`scripts/firestore-backup.js`는 다음을 포함해야 한다.

- 구성원 `role`
- 집안일 포인트/XP
- 육아 항목 이름
- 육아 포인트 수신자
- 설정 변경 요청
- 아침 브리핑의 pending item changes

관련 함수:

- `dailySummary(state, date)`
- `markdownReport(state, summary)`
- `morningBriefing(state, date)`

## 수정 시 주의사항

- 저장 레이어 자체는 건드리지 않는다.
  - `saveState()`
  - `saveStateOptimistic()`
  - Firestore provider
  - localStorage provider
- 새 상태 필드는 반드시 `defaultState()`와 `normalizeState()`를 함께 수정한다.
- 기존 저장 데이터에 없는 필드는 기본값으로 보정한다.
- 브라우저에 GitHub token을 저장하지 않는다.

## 검증 명령

```powershell
node --check scripts/firestore-backup.js
npm.cmd test
```
