# ForHome 웹·모바일 이중 클라이언트 분리 보고서

- **작성일:** 2026-06-25
- **브랜치:** `260624_ej`
- **원격:** `https://github.com/jenneyChun/forhome.git`
- **참고 디자인:** [urichib](https://github.com/silverpine-park/urichib) 디자인 핸드오프 (urichib UX 토큰·모바일 탭 패턴)

---

## 1. 개요

기존 단일 `code/index.html` + `data-surface` CSS 분기 방식을 폐기하고, **같은 API 서버(8080)** 위에서 **Host 헤더**로 웹·모바일 클라이언트를 분리했습니다.

| 클라이언트 | 로컬 URL | 정적 루트 | 레이아웃 |
|-----------|----------|-----------|----------|
| 웹(PC) | `http://localhost:8080` | `code/web/` | 좌측 sticky 탭, 12열 grid |
| 모바일 | `http://m.localhost:8080` | `code/mobile/` | 하단 5탭, 단일 컬럼 |

기능 범위는 웹과 **동일(full parity)**: 브리핑·기록·확인·내일·설정.

---

## 2. 아키텍처

```text
Browser (localhost:8080)  ──┐
                            ├──> server/server.ps1 :8080
Browser (m.localhost:8080) ─┘         │
                                      ├─ Host → code/web/ | code/mobile/
                                      ├─ /shared/* → code/shared/
                                      ├─ /auth-invitation/* → code/auth-invitation/
                                      └─ /api/* → PostgreSQL (server/db.ps1)
```

공통 로직은 [`code/shared/forhome-core.js`](../code/shared/forhome-core.js) 한 곳에서 관리합니다. 웹·모바일 HTML은 셸(shell)만 다르고 `ForHomeApp.boot({ surface: 'web' | 'mobile' })`로 기동합니다.

---

## 3. 주요 변경 파일

| 경로 | 역할 |
|------|------|
| [`code/web/index.html`](../code/web/index.html) | PC 웹 셸 |
| [`code/mobile/index.html`](../code/mobile/index.html) | 모바일 셸 |
| [`code/shared/forhome-core.js`](../code/shared/forhome-core.js) | 상태·API·render·이벤트 (기존 index.html JS 추출) |
| [`code/shared/tokens.css`](../code/shared/tokens.css) | urichib 디자인 토큰·공통 컴포넌트 스타일 |
| [`code/shared/web.css`](../code/shared/web.css) | PC 좌측 탭·12열 grid |
| [`code/shared/mobile.css`](../code/shared/mobile.css) | 하단 탭바·모바일 단일 컬럼 |
| [`server/server.ps1`](../server/server.ps1) | Host 라우팅, CORS, 쿠키 Domain |
| [`tests/playwright.config.js`](../tests/playwright.config.js) | mobile → `http://m.localhost:8080` |
| [`tests/run-tests.ps1`](../tests/run-tests.ps1) | 신규 경로 구조 검증 |

레거시 [`code/index.html`](../code/index.html)은 `/` 리다이렉트 stub만 유지합니다(직접 서빙되지 않음).

---

## 4. 서버 변경 상세

[`server/server.ps1`](../server/server.ps1):

- `Get-SurfaceClientRoot`: `Host`가 `m.`로 시작하면 `code/mobile`, 아니면 `code/web`
- `/shared/` 요청은 Host와 무관하게 `code/shared/`에서 제공
- `$script:AllowedOrigins`에 `m.localhost`, `m.<LAN IP>` 추가
- `FORHOME_COOKIE_DOMAIN` 환경변수로 세션 쿠키 Domain 설정 (로컬: `.localhost`)

서버 시작 시 출력:

```text
Web:    http://localhost:8080
Mobile: http://m.localhost:8080
LAN:    http://<ip>:8080  |  http://m.<ip>:8080
```

---

## 5. UX·디자인

- **공통:** urichib 디자인 토큰(코랄 `#FF7E67`, Gothic A1 + Nunito, 카드 radius 20px 등)
- **웹:** 좌측 탭(🏠 브리핑 · 📋 기록 · ✅ 확인 · 📅 내일 · ⚙️ 설정), 다열 패널
- **모바일:** urichib 스타일 하단 탭, 브리핑 헤더(인사·포인트 히어로), 동일 `data-testid` 유지

초대 URL 기본 모바일 베이스: [`code/auth-invitation/forhome-auth-invitation.js`](../code/auth-invitation/forhome-auth-invitation.js)의 `createDefaultMobileBaseUrl()` → 로컬에서 `http://m.localhost:8080`

---

## 6. 세션·쿠키

`localhost`와 `m.localhost`는 origin이 달라 기본 쿠키는 공유되지 않습니다.

로컬에서 한 번 로그인으로 양쪽 사용:

```powershell
# data/db.env.ps1
$env:FORHOME_COOKIE_DOMAIN = ".localhost"
```

배포 시 `.yourdomain.com` 형태로 설정합니다.

---

## 7. 테스트

| 항목 | 명령 | 결과 |
|------|------|------|
| 구조 테스트 | `npm test` / `tests/run-tests.ps1` | Host 라우팅·신규 경로 검증 PASS |
| E2E desktop | `npm run test:e2e -- --project=desktop` | 기존 플로우 유지 |
| E2E mobile smoke | `login-navigation.spec.js` | `m.localhost:8080` 로그인·홈 표시 |

Playwright mobile 프로젝트 baseURL: `http://m.localhost:8080`

---

## 8. 로컬 실행

```bash
npm run setup:db   # 최초 1회
npm run dev:local
```

- 웹: http://localhost:8080
- 모바일: http://m.localhost:8080
- 테스트 mock: `?storage=test` (양쪽 URL 모두)

---

## 9. 문서 갱신

- [`README.md`](../README.md), [`README.ko.md`](../README.ko.md): 웹·모바일 클라이언트 섹션
- [`docs/architecture.md`](../docs/architecture.md): 이중 클라이언트 구조
- [`docs/current-features.md`](../docs/current-features.md): 클라이언트 경로
- [`docs/agents/frontend-brief.md`](../docs/agents/frontend-brief.md), [`docs/agents/backend-brief.md`](../docs/agents/backend-brief.md): 파일 경로 갱신

---

## 10. GitHub 반영

- **브랜치:** `260624_ej`
- **커밋:** 웹·모바일 분리 + Report + README 갱신
- **main:** PR merge 후 반영 권장

---

## 11. 후속 과제 (선택)

- Playwright mobile 프로젝트 전체 E2E 확대
- 모바일 전용 render wrapper(브리핑 카드 레이아웃) 추가 다듬기
- 프로덕션 리버스 프록시(`m.` 서브도메인) 설정 가이드 문서화
