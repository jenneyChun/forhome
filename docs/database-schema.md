# Database Schema

## 현재 사용 중인 저장소

### 코드에서 확인된 내용

현재 운영 저장소는 Cloud Firestore이며, 핵심 데이터는 단일 문서에 저장된다.

```text
families/forhome/state/app
```

이 문서는 브라우저 앱의 상태 객체와 같은 구조를 가진다.

## Firestore 문서 구조

### `families/forhome/state/app`

확인된 최상위 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `version` | number | 저장 버전. 저장 시 증가한다. |
| `updatedAt` | string | 마지막 갱신 시각 ISO 문자열. |
| `settings` | object | 앱 설정. |
| `members` | array | 가족 구성원 목록. |
| `accounts` | array | 앱 내부 계정 매핑. |
| `chores` | array | 집안일 마스터 목록. |
| `history` | array | 완료 기록과 승인 상태. |
| `tomorrowPlans` | array | 내일/날짜별 할 일 요청. |
| `messages` | array | 가족 메시지. |
| `badgeHistory` | array | 뱃지 획득 기록. |
| `careAssignments` | array | 날짜별 아침/저녁 육아 담당. |
| `careSessions` | array | 육아 시간 기록. |

## 세부 객체 구조

### `settings`

코드에서 확인된 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `vacationThreshold` | number | 주간 피로도 휴식 임계값. 기본값 25. |
| `weekStartsOn` | number | 주 시작 요일. 기본값 1. |

### `members[]`

코드에서 확인된 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 구성원 ID. |
| `name` | string | 표시 이름. |
| `emoji` | string | 아바타 표시값. |
| `restricted` | boolean | 본인/관리자 기록 제한 여부. |
| `color` | string | 구성원 색상. |
| `xp` | number | 승인된 XP 합계. |
| `totalFatigue` | number | 승인된 피로도 합계. |
| `completedTasks` | number | 승인된 완료 수. |
| `stickers` | number | 스티커 수. |
| `onVacation` | boolean | 주간 피로도 기준 휴식 여부. |
| `earnedBadges` | array | 획득한 뱃지 ID 목록. |

### `accounts[]`

코드에서 확인된 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 로그인 ID. |
| `password` | string | 앱 내부 비밀번호. |
| `memberId` | string/null | 연결된 구성원 ID. |
| `isAdmin` | boolean | 관리자 여부. |

주의: 운영 로그인은 Firebase Auth를 사용하지만, 앱 내부 권한과 구성원 연결은 이 배열도 함께 사용한다.

### `chores[]`

코드에서 확인된 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 집안일 ID. |
| `name` | string | 집안일 이름. |
| `emoji` | string | 표시값. |
| `fatigue` | number | 피로도 점수. |
| `xp` | number | XP 점수. |
| `category` | string | `house`, `care`, `pet`, `child` 등. |

### `history[]`

코드에서 확인된 필드:

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 기록 ID. |
| `memberId` | string | 작업 수행자. |
| `choreId` | string | 집안일 ID. |
| `choreName` | string | 기록 당시 집안일 이름. |
| `choreEmoji` | string | 기록 당시 표시값. |
| `category` | string | 카테고리. |
| `fatigueAdded` | number | 추가 피로도. |
| `xpEarned` | number | 획득 XP. |
| `timestamp` | number | 완료 시각 밀리초. |
| `verificationStatus` | string | `pending`, `approved`, `rejected`. |
| `reviewerId` | string/null | 대표 검토자. |
| `reviewedBy` | string/null | 검토한 사용자. |
| `reviewedAt` | number/null | 검토 시각. |
| `reviewNote` | string | 검토 메모. |
| `approvalRequests` | array | 검토자별 승인 요청. |
| `proofImage` | string | 사진 data URL. |
| `proofImageName` | string | 원본 파일명. |
| `proofCaption` | string | 사용자가 남긴 메모. |
| `proofAnalysis` | string | 이미지 처리 설명. |

### `approvalRequests[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `reviewerId` | string | 승인자 ID. |
| `status` | string | `pending`, `approved`, `rejected`. |
| `reviewedAt` | number/null | 검토 시각. |
| `reviewNote` | string | 검토 메모. |

### `tomorrowPlans[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 요청 ID. |
| `fromId` | string | 요청자. |
| `toId` | string | 받는 사람. |
| `choreId` | string | 집안일 ID. |
| `title` | string | 표시 제목. |
| `note` | string | 요청 메모. |
| `targetDate` | string | 대상 날짜 `YYYY-MM-DD`. |
| `status` | string | `open`, `closed`. |
| `requestStatus` | string | `pending`, `accepted`, `declined`. |
| `declineReason` | string | 거절 이유. |
| `respondedAt` | number/null | 응답 시각. |
| `createdAt` | number | 생성 시각. |

### `messages[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 메시지 ID. |
| `fromId` | string | 보낸 사람. |
| `toId` | string/null | 받는 사람. 없으면 전체. |
| `text` | string | 메시지 본문. |
| `timestamp` | number | 생성 시각. |

### `badgeHistory[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 기록 ID. |
| `memberId` | string | 구성원 ID. |
| `badgeId` | string | 뱃지 ID. |
| `name` | string | 뱃지 이름. |
| `emoji` | string | 표시값. |
| `timestamp` | number | 획득 시각. |

### `careAssignments[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `date` | string | 날짜 `YYYY-MM-DD`. |
| `morningId` | string | 아침 담당자. |
| `eveningId` | string | 저녁 담당자. |
| `updatedAt` | number | 갱신 시각. |

### `careSessions[]`

| 필드 | 타입 | 설명 |
| --- | --- | --- |
| `id` | string | 기록 ID. |
| `date` | string | 날짜 `YYYY-MM-DD`. |
| `memberId` | string | 담당자. |
| `startTime` | string | 시작 시간. |
| `endTime` | string | 종료 시간. |
| `minutes` | number | 총 분. |
| `note` | string | 메모. |
| `createdAt` | number | 생성 시각. |

## 기타 Firestore 경로

### 코드에서 확인된 내용

Firestore rules에는 아래 경로가 언급된다.

```text
families/{familyId}/memberships/{uid}
```

해당 멤버십 문서가 있으면 허용된 이메일 목록에 없어도 읽기/쓰기를 허용한다.

### 추정한 내용

- `memberships`는 향후 초대 또는 UID 기반 권한 확장을 위한 구조로 보인다.
- 현재 브라우저 코드에서 멤버십 문서를 직접 생성하거나 관리하는 흐름은 확인되지 않는다.

## PostgreSQL 스키마

### 코드에서 확인된 내용

`server/sql/schema.sql`에는 PostgreSQL 테이블 정의가 있다.

- `app_version`
- `settings`
- `members`
- `accounts`
- `chores`
- `history`
- `messages`
- `badge_history`
- `member_badges`

### 추정한 내용

- 이 스키마는 현재 운영 저장소가 아니라 이전 구현 또는 향후 참고용 레거시 구조다.
- 현재 `history` 테이블에는 최신 승인/증빙 필드가 모두 반영되어 있지 않아 Firestore 모델과 차이가 있다.

