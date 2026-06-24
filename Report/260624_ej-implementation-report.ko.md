# ForHome `260624_ej` 브랜치 구현 보고서

- **작성일:** 2026-06-24
- **브랜치:** `260624_ej` (main 미반영)
- **원격:** `https://github.com/jenneyChun/forhome.git`
- **최종 커밋:** `c0e9749`

---

## 1. 개요

`260624_ej` 브랜치는 ForHome 로컬 개발 환경 안정화, 로그인·인증 수정, 헤더 UI 개선, 로그인 후 화면 전환 속도 개선, 데이터 로딩 성능 최적화(AARRR 방법론)를 목표로 진행되었습니다.

모든 변경은 `main`이 아닌 `260624_ej`에만 커밋·push 되었습니다.

---

## 2. 커밋 이력 요약

| 커밋 | 제목 | 핵심 내용 |
|------|------|-----------|
| `0bb1c7f` | fix: reliably free port 8080 | psql 자식 프로세스 등으로 8080 점유 시 정리 로직 강화 |
| `be7f9f6` | Fix PostgreSQL auth + admin login | `setup:db`, `db.env.ps1`, admin/admin1234 로그인 |
| `50c53d0` | Fix post-login navigation | `showApp()` 선호출, DB 초기화 캐시 |
| `8536082` | Fix household name in profile | 프로필 API 가족 이름 업데이트 |
| `e050037` | instant login screen transition (TDD) | `loadStateInBackground`, 로그인 네비게이션 E2E |
| `c0e9749` | AARRR data loading perf | psql 배치화, summary API, smart sync, lazy proof |

---

## 3. 구현 상세

### 3.1 개발 서버 기동 (`npm run dev`)

**문제:** 8080 포트 충돌, LAN IP 접근 불가

**해결:**
- [`server/server.ps1`](../server/server.ps1): 포트 정리(`Stop-ProcessTree`, `taskkill /T`), `0.0.0.0` 바인딩, LAN CORS
- [`scripts/free-port.ps1`](../scripts/free-port.ps1): 수동 포트 해제 스크립트
- [`docker-compose.yml`](../docker-compose.yml), [`scripts/setup-local-db.ps1`](../scripts/setup-local-db.ps1): 로컬 DB 셋업

**접속 URL:**
- PC: `http://localhost:8080`
- LAN: `http://10.102.235.135:8080`

---

### 3.2 PostgreSQL 인증 및 admin 로그인

**문제:** `postgres` password 인증 실패, admin/admin1234 로그인 불가, API 400/503

**해결:**
- [`data/db.env.ps1`](../data/db.env.example.ps1) 자동 생성 (`npm run setup:db`)
- [`server/db.ps1`](../server/db.ps1): `PGUSER` 고정, `Invoke-PsqlNative` 래퍼
- 기본 계정: **admin / admin1234**

**최초 실행:**
```bash
npm run setup:db   # 1회
npm run dev:local
```

---

### 3.3 로그인 후 화면 전환

**문제:** 로그인 성공 후에도 로그인 화면에 20~30초 머무름

**원인:** `loadState()`(느린 `/api/state`) 완료 후에야 `showApp()` 호출

**해결:**
- [`code/index.html`](../code/index.html): 로그인 API 성공 직후 `showApp()` → 데이터는 백그라운드 로드
- [`server/db.ps1`](../server/db.ps1): `Initialize-Database` 프로세스당 1회 캐시
- 로딩 오버레이(`#appLoading`) 및 bootstrap 데이터(가족명, 표시이름)로 헤더 즉시 렌더

---

### 3.4 헤더 UI (가족 이름 · 프로필 드롭다운)

**요구사항:**
1. 좌측에 가족이 지은 이름 표시
2. 우측 프로필 pill 클릭 → 설정 / 로그아웃 드롭다운
3. 설정 → 계정 정보 수정 페이지

**구현:**
- `#familyName`: `state.householdName` 동적 표시 (없으면 「우리집 히어로」)
- `#userDropdown`: 설정(`section-account`), 로그아웃
- API: `GET/PATCH /api/profile`

---

### 3.5 AARRR 데이터 로딩 최적화

**문제:** 로그인 후 「데이터 불러오는 중...」 10~20초

**근본 원인:** `Get-DbState`가 18회 순차 `psql` 프로세스 실행 + 전체 state(이미지 포함) 로드

| AARRR 단계 | ForHome 의미 | 적용 |
|------------|--------------|------|
| **Activation** | 로그인 후 첫 가치(홈 탭) | `GET /api/state/summary` → 3초 이내 홈 표시 |
| **Retention** | 재방문·폴링 | `GET /api/state/version` + `sinceVersion` 조건부 동기화 |
| **Revenue** | 기록·승인 완료 | summary 로드 후 오버레이 해제, optimistic 저장 유지 |

**성능 (실측):**

| API | 이전 | 이후 |
|-----|------|------|
| `Get-DbState` | ~12.6초 | **~0.8초** |
| `Get-DbStateSummary` | — | **~0.7초** |
| `Get-DbStateVersion` | — | **~0.6초** |

**주요 기술 변경:**
- `Invoke-PsqlCsvBatch`: 18회 psql → 1회 배치
- `GET /api/state/summary`, `/api/state/version`, `/api/state?sinceVersion=N`
- `GET /api/tasks/:id/proof`: proof_image lazy load
- 프론트 `loadSummaryThenFull()`: 요약 → 전체 순차 로드

---

## 4. 테스트

| 테스트 | 경로 | 내용 |
|--------|------|------|
| 구조 테스트 | `npm test` | API·스키마·파일 존재 검증 |
| 성능 테스트 | `tests/powershell/login-performance.ps1` | `RUN_DB_TESTS=1` 시 DB SLA |
| E2E | `npm run test:e2e` | `tests/e2e/login-navigation.spec.js` — 500ms 화면 전환, 3초 홈 SLA |

---

## 5. 로컬 실행 가이드

```bash
git checkout 260624_ej
npm run setup:db      # 최초 1회
npm run dev:local
```

브라우저: `http://localhost:8080`  
로그인: **admin / admin1234**

---

## 6. GitHub 반영

- **Push 대상:** `origin/260624_ej` only
- **main:** 미반영 (merge/push 없음)
- **PR 생성 (선택):** https://github.com/jenneyChun/forhome/pull/new/260624_ej

---

## 7. 후속 과제 (선택)

- `Get-DbState` 추가 SQL 최적화(인덱스, 단일 JOIN 쿼리)
- Playwright mobile 프로젝트 안정화 (서버 단일 스레드 부하)
- PBKDF2 iteration 조정은 보안 검토 후 별도 진행
