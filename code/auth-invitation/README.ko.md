# Auth Invitation Module

`forhome-auth-invitation.js`는 대표 가입, 가족 초대장, 역할 기반 합류 로직을 모아둔 브라우저용 모듈이다.

## 로드

```html
<script src="/auth-invitation/forhome-auth-invitation.js"></script>
```

로드 후 `window.ForHomeAuthInvitation` 전역 객체를 사용할 수 있다.

## 기본 사용 예

```js
const authInvite = window.ForHomeAuthInvitation;
const repository = authInvite.createLocalStorageInvitationRepository();
const service = authInvite.createAuthInvitationService({
  repository,
  baseUrl: 'https://forhome.example.com',
  mobileBaseUrl: 'https://m.forhome.example.com'
});

const owner = await service.registerOwner({
  uid: 'uid-admin',
  email: 'admin@example.com',
  displayName: '대표',
  householdName: '우리집'
});

const created = await service.createInvite({
  householdId: owner.household.householdId,
  createdBy: owner.member.uid,
  roleHint: 'hero',
  roleLocked: false,
  displayNameHint: '초대받은 사람'
});

console.log(created.share.mobileUrl);
console.log(created.share.shortCode);
console.log(created.share.qrPayload);
```

## 역할

| 표시명 | 내부값 | 의미 |
| --- | --- | --- |
| 대표 히어로 | `owner` | 집 생성자, 구성원/초대 관리 권한 |
| 홈 히어로 | `hero` | 집안일과 돌봄을 수행하는 구성원 |
| 케어 멤버 | `care_member` | 돌봄을 받거나 지원 대상이 되는 구성원 |

기존 `adult`는 `hero`, 기존 `child`는 `care_member`로 정규화된다.

## 초대 방식

모듈은 초대장을 만들 때 다음 값을 함께 반환한다.

- `share.webUrl`: 웹용 초대 URL
- `share.mobileUrl`: 모바일용 초대 URL
- `share.qrPayload`: QR 코드에 넣을 URL
- `share.shortCode`: 직접 입력 가능한 초대 번호
- `share.message`: 카카오톡/문자 공유용 메시지

QR 이미지를 직접 그릴 때는 `renderQrCode(container, payload)`를 사용할 수 있다. 이 함수는 `window.QRCode` 렌더러가 먼저 로드되어 있으면 QR을 그리고, 없으면 URL을 복사할 수 있는 fallback을 표시한다.

## 저장소

현재 구현은 두 저장소를 제공한다.

- `createMemoryInvitationRepository()`: 테스트와 임시 실행용
- `createLocalStorageInvitationRepository()`: 브라우저 localStorage mock용

운영 연동은 `server/server.ps1`의 PostgreSQL API가 담당한다. 이 모듈을 화면에 붙일 때는 같은 메서드 이름을 가진 API repository를 추가하거나, `/api/auth/register-owner`, `/api/invites`, `/api/invites/:id` 응답을 그대로 사용한다.
