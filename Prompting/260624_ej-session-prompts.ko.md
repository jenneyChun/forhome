# ForHome `260624_ej` 세션 프롬프트 정리

이 문서는 2026-06-24 Cursor 세션에서 사용자가 요청한 작업과, 에이전트에게 전달한(또는 유도된) 프롬프트를 재사용 가능한 형태로 정리한 것입니다.

---

## 공통 규칙 (세션 전체 적용)

```
- 작업 브랜치: 260624_ej (main에 반영·push 금지)
- 기능 구현 후 GitHub push는 260624_ej만
- commit description에 코드 수정 내용 + 사용자 요청 사항 반드시 포함
```

---

## 1. 브랜치 생성

**사용자 요청:**
> branch를 main으로 하지 말고 신규 branch 260624_ej를 만들어서 거기에서 코드 구현을 하자

**에이전트 지시 요약:**
- `git checkout -b 260624_ej`
- 미커밋 변경 유지, main 미반영

---

## 2. 8080 포트 · LAN 접근

**사용자 요청:**
> 8080포트가 열려있다면 그걸 제거하고 다시 열리도록 하고 현재 ip 10.102.235.135에서도 열리도록 해줘.

**재사용 프롬프트:**
```
ForHome 프로젝트 server/server.ps1 수정:
1. 8080 포트 점유 프로세스 자동 정리 후 서버 기동
2. 0.0.0.0 또는 LAN IP(10.102.235.135)에서 접근 가능하도록 바인딩
3. CORS에 LAN origin 추가
4. npm run dev 로 검증
브랜치: 260624_ej, main push 금지
```

---

## 3. npm run dev 항상 기동

**사용자 요청:**
> 여전히 npm run dev으로 웹페이지가 열리지 않고 있다. 늘 테스트를 위해서 앱이 실행될 수 있도록 수정해

**재사용 프롬프트:**
```
npm run dev 가 항상 성공하도록 수정:
- psql 자식 프로세스 등 zombie PID로 8080 점유 시 트리 종료
- server.ps1 포트 정리 로직 강화 (taskkill /T, 재시도)
- 검증 후 260624_ej 커밋·push
```

---

## 4. PostgreSQL · admin 로그인

**사용자 요청:**
> admin / admin1234로 로그인이 되어야 한다. postgres password 인증 실패 해결.

**재사용 프롬프트:**
```
ForHome 로그인 실패 수정:
- data/db.env.ps1 생성 (npm run setup:db)
- server/db.ps1 PGUSER/PGPASSWORD 안정화
- admin/admin1234 시드 계정 로그인 E2E 검증
- 400/503 오류 원인 제거
브랜치: 260624_ej
```

---

## 5. 로그인 후 화면 전환 분석

**사용자 요청:**
> 로그인 할때 너무 오래걸린다. 로그인 하면 바로 화면 페이지 전환되도록. TDD 방식으로 개발.

**재사용 프롬프트 (TDD Red):**
```
tests/e2e/login-navigation.spec.js 추가:
- Postgres/mock 경로에서 로그인 API 응답 후 500ms 이내 #app-shell 표시
- 동기화 완료 전에도 로그인 화면 hidden 확인

tests/powershell/login-performance.ps1:
- RUN_DB_TESTS=1 시 Login-DbUser, Get-DbState 시간 측정
```

**재사용 프롬프트 (TDD Green):**
```
code/index.html:
- doLogin: login() 후 즉시 showApp(), loadState는 loadStateInBackground()
- init 세션 복원도 동일 패턴
- server.ps1 기동 시 Initialize-Database warm-up
- login 응답에 householdName, displayName, memberEmoji bootstrap
```

---

## 6. 헤더 UI

**사용자 요청:**
> 1. 우리집 히어로 → 가족 이름 표시
> 2. 프로필 pill → 설정 페이지
> 3. 드롭다운: setting, logout

**재사용 프롬프트:**
```
code/index.html 헤더 수정:
- #familyName ← state.householdName (fallback: 우리집 히어로)
- #currentUser 클릭 → #userDropdown (설정/로그아웃)
- section-account 계정 수정 폼 + GET/PATCH /api/profile
기존 UI 스타일(cream header, pill) 유지
```

---

## 7. AARRR 데이터 로딩 최적화

**사용자 요청:**
> 로그인 이후 데이터 불러오는데 시간이 많이 걸린다. AARRR로 분석하고 개선 방법론 적용.

**재사용 프롬프트 (분석):**
```
로그인 후 데이터 로딩 지연 AARRR 분석:
- Activation: 홈 탭 TTI North Star < 3초
- Retention: 5초 폴링 full state 부하
- 병목: Get-DbState 18회 psql spawn (~12초)
개선 로드맵: 배치 SQL → summary API → version sync → lazy proof
```

**재사용 프롬프트 (구현):**
```
Phase 2: server/db.ps1 Invoke-PsqlCsvBatch, Get-DbState < 5초
Phase 3: GET /api/state/summary + loadSummaryThenFull(), 홈 3초 E2E
Phase 4: GET /api/state/version, subscribeState version polling
Phase 5: history에서 proof_image 제외, GET /api/tasks/:id/proof
TDD: login-performance.ps1 SLA 갱신
브랜치: 260624_ej, push only
```

---

## 8. GitHub push

**사용자 요청:**
> github push 해줘 / commit description에 요청 내용 정리

**재사용 프롬프트:**
```
git push -u origin 260624_ej
- main push 금지
- 커밋 메시지에 변경 코드 + 사용자 요청 사항 포함 (HEREDOC)
- jenneyChun 계정 권한 확인 (gh auth login)
```

---

## 9. 보고서·문서화 (본 요청)

**사용자 요청:**
> 구현한 내용 Report 폴더에 보고서, Prompting 폴더에 프롬프트 정리, github 반영

**산출물:**
- `Report/260624_ej-implementation-report.ko.md`
- `Prompting/260624_ej-session-prompts.ko.md` (본 문서)

---

## 프롬프트 작성 팁

1. **브랜치·push 규칙**을 맨 위에 명시하면 main 오반영 방지
2. **측정 가능한 SLA**를 포함하면 TDD 테스트 작성이 수월함 (예: 500ms, 3초)
3. **파일 경로**를 구체적으로 지정하면 범위 축소에 유리 (`server/db.ps1`, `code/index.html`)
4. **검증 명령**을 함께 요청: `npm test`, `npm run test:e2e`, `RUN_DB_TESTS=1`
