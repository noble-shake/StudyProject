# 프런트엔드 코드 노출 — F12로 다 보이는 JS, 난독화가 답이 될 수 있는가

---

- **카테고리**: 웹 개발, 네트워크/보안
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`

---

## 출처

2026-09-08, 사용자가 시니어 백엔드 개발자에게 코드 리뷰를 받으며 "브라우저 개발자도구(F12)를
열면 프런트 JS 소스가 그대로 보인다"는 점을 지적받았다 — RottenNobleProject의 직접 코드 학습
세션에서 나온 주제로, 별도 `STUDY-nn` 백로그 항목은 아니다. 같은 날 다른 세션이 PHP 백엔드
보안 패치(`CODE_MEMO.md`의 `MEMO-WEB-09`)를 검토하며 "프런트 JS 난독화는 실효성이 없어
보류"라고 판단한 적이 있는데, 이 문서는 그 판단이 정확히 왜 맞는지를 짚는다.

## 정의

브라우저에서 실행되는 모든 JavaScript/CSS/HTML은 정의상 **클라이언트에게 전달되어야 실행할 수
있는 코드**다. 서버가 아무리 애를 써도, 브라우저가 그 코드를 읽고 실행할 수 있어야 화면이 동작
하므로, 그 코드는 반드시 사용자의 기기에 평문(또는 평문으로 되돌릴 수 있는 형태)으로 도착한다.
난독화(obfuscation)는 변수명을 의미 없는 문자로 바꾸고 코드 구조를 읽기 어렵게 뒤섞는 기법이지만,
**실행 가능한 상태를 유지해야 하므로 원리적으로 되돌릴 수 있다** — 이건 암호화(encryption)와
근본적으로 다른 성질이다.

## 요약

F12로 보이는 걸 막을 방법은 없다 — 난독화는 "읽기 귀찮게" 만들 뿐 "못 읽게" 만들지 못한다.
그래서 진짜 방어선은 "프런트 코드를 숨기는 것"이 아니라 "프런트 코드에 애초에 숨길 게 없게
만드는 것"이다. RottenNobleProject는 이미 이 원칙을 따르고 있다 — 실제로 확인해보니 프런트
코드에는 비밀번호 해시, DB 접속정보, 서명 키 같은 진짜 비밀값이 전혀 들어있지 않다.

## 상세

### 왜 난독화가 "보안"이 아닌가 — security through obscurity

난독화 코드의 예를 보자:

```javascript
// 원본 (Vite 개발 모드)
function login(username, password) {
  return fetch(`${API_BASE_URL}/auth/login`, { ... });
}

// 난독화 후 (예시 — 도구가 이런 식으로 변환한다)
function _0x4a2f(_0x1a,_0x2b){return fetch(_0x3c[0]+"/auth/login",{...})}
```

읽기는 확실히 불편해졌다. 하지만 브라우저는 여전히 이 코드를 **그대로 실행**해야 하므로, 개발자
도구에서 실행 중인 함수에 브레이크포인트를 걸거나, 네트워크 탭에서 실제로 어떤 요청이 나가는지
관찰하거나, 도구(디난독화기)를 돌리면 원래 로직을 다시 읽어낼 수 있다. 이런 상태에 의존하는
방어를 "security through obscurity"(모호함을 통한 보안)라고 부르는데, 보안 업계에서는 이걸
**진짜 보안 계층으로 인정하지 않는다** — 시간과 노력의 장벽을 조금 높일 뿐, 뚫리지 않는다는
보장이 전혀 없기 때문이다. Kerckhoffs의 원칙(암호 시스템은 알고리즘이 공개돼도 키만 안전하면
안전해야 한다)이 이 분야의 오래된 기본 전제다 — "숨기면 안전하다"가 아니라 "공개돼도 안전해야
진짜 안전한 것"이라는 사고방식이다.

### 이 프로젝트의 프런트 코드에 실제로 무엇이 들어있는지 확인

RottenNobleProject의 프런트 빌드 결과물(`frontend/dist/assets/*.js`)에 실제로 무엇이 박혀있는지
점검했다:

- `import.meta.env.VITE_API_BASE_URL` → `https://api.rotten-noble.com/api` — 이건 애초에
  비밀이 아니다. 누구나 브라우저 주소창에 쳐서 확인할 수 있는 공개 API 주소다.
- 관리자 토큰(`rottennoble_admin_token`) — 로그인에 **성공한 사용자의 브라우저**의
  `localStorage`에만 존재한다. 프런트 **코드**(정적 JS 파일) 안에는 토큰 값 자체가 들어있지
  않다 — 코드는 "로그인 후 토큰을 받아서 저장하는 로직"만 담고 있지, 토큰 값 자체를
  하드코딩하고 있지 않다.
- 관리자 비밀번호/해시 — 서버(`backend-spring`)의 환경변수(`ADMIN_PASSWORD_HASH`)에만
  존재하고, 어떤 API 응답에도 포함되지 않는다. 프런트가 그 값을 받아본 적이 없으니, 프런트
  코드를 아무리 읽어도 나올 수 없다.
- DB 접속정보, Redis 접속정보 — 전부 백엔드 컨테이너의 환경변수(`.env.prod`)에만 있고, 프런트
  빌드 산출물과는 완전히 분리된 영역이다.

즉 "숨겨야 할 게 코드 안에 없다"는 게 실제로 확인되는 상태다 — 난독화가 필요 없는 게 아니라,
난독화로 지켜야 할 대상 자체가 애초에 설계상 프런트에 안 들어가게 되어 있다.

### 그럼 진짜 방어선은 어디인가

이 프로젝트의 진짜 방어는 **서버 쪽 인가(authorization) 검사**다:

```java
// backend-spring — AdminSessionInterceptor.java
if (handlerMethod.getMethodAnnotation(RequireAdmin.class) == null) {
    return true; // 인증 불필요 엔드포인트는 통과
}
String token = adminSessionService.extractToken(request);
if (!adminSessionService.isValidToken(token)) {
    throw new UnauthorizedException(...); // 유효한 토큰 없인 여기서 막힌다
}
```

프런트에서 "글쓰기" 버튼을 숨기거나 비활성화하는 건 **사용자 경험(UX)**을 위한 것이지 **보안**이
아니다 — 공격자는 브라우저 UI를 거치지 않고 `curl`로 직접 `POST /api/posts`를 호출할 수 있으므로,
"버튼이 안 보인다"는 아무 방어도 되지 못한다. 실제 방어는 그 요청이 서버에 도착했을 때
`AdminSessionInterceptor`가 Redis에 저장된 유효한 세션인지를 검사하는 지점 하나뿐이다. 이걸
"신뢰 경계(trust boundary)"라고 부르는데, **클라이언트(브라우저)는 절대 신뢰 경계 안쪽에 둘 수
없다** — 사용자가 개발자도구로 무엇이든 조작할 수 있는 환경이기 때문이다.

### 소스맵(source map)은 별개 문제

난독화와 헷갈리기 쉬운 인접 주제로 소스맵이 있다 — 원본 코드와 빌드된 코드를 매핑해주는
파일로, 프로덕션에 실수로 배포하면 난독화/압축 이전의 원본 코드를 그대로 복원해서 보여준다.
이 프로젝트의 Vite 프로덕션 빌드(`npm run build`)는 `build.sourcemap` 옵션을 켜지 않아
기본값(비활성)을 따르므로, 실제 배포 산출물(`frontend/dist/assets/`)에 `.map` 파일이 전혀
포함되지 않는 것을 확인했다 — 이 부분은 의도치 않게라도 이미 안전한 상태다.

## 비교표

| 방법 | 무엇을 막는가 | 진짜 보안인가 | 이 프로젝트의 선택 |
|---|---|---|---|
| JS 난독화 | 코드를 "읽기 귀찮게" | 아니다(되돌릴 수 있음) | 적용 안 함 |
| 소스맵 미배포 | 원본 코드/변수명 복원 | 부분적(방어 심층화 정도) | 이미 기본값으로 미배포 |
| 프런트에 비밀값 자체를 안 둠 | 비밀값 유출 자체를 원천 차단 | 그렇다 | 적용 중 |
| 서버 쪽 인가 검사 | 실제 무단 조작(쓰기·삭제 등) | 그렇다(진짜 신뢰 경계) | 적용 중 (`AdminSessionInterceptor`) |

## 질문

- **Q. 그럼 난독화는 아예 쓸모가 없나?**
  A. 완전히 무의미하진 않다 — 자동화된 스크래핑 봇이 특정 패턴을 문자열 매칭으로 찾는 걸 살짝
  방해하거나, 경쟁사가 UI 로직을 그대로 복사해가는 걸 조금 늦추는 정도의 실익은 있다. 다만 이건
  "보안"이 아니라 "귀찮게 하기"의 영역이고, 이 프로젝트처럼 지켜야 할 진짜 비밀이 프런트에 없는
  경우엔 들일 노력 대비 얻는 게 거의 없다고 판단했다.

- **Q. Vite의 프로덕션 빌드가 하는 압축(minify)도 일종의 난독화 아닌가?**
  A. 목적이 다르다. Minify는 변수명을 짧게, 공백을 제거해 **파일 크기를 줄이는** 최적화가
  1차 목적이고, 읽기 어려워지는 건 부수 효과다. 난독화 전용 도구(예: `javascript-obfuscator`)는
  파일 크기와 무관하게 **의도적으로 읽기 어렵게 만드는 것 자체**가 목적이라는 점에서 다르다.
  RottenNobleProject는 Vite 기본 minify만 쓰고 별도 난독화 도구는 안 쓴다.

- **Q. 그럼 API 키나 서드파티 서비스 키가 필요해지면 어떻게 하나?**
  A. 그 키가 "공개돼도 되는 키"(예: 요청 출처 제한이 걸린 클라이언트 키)인지 "절대 노출되면
  안 되는 키"(예: 결제 API의 시크릿 키)인지부터 구분해야 한다. 후자는 절대 프런트 코드에 두지
  않고, 항상 백엔드가 대신 호출해주는 프록시 패턴을 쓴다 — 이 프로젝트가 지금 하고 있는 것과
  같은 원칙(비밀은 서버에만)의 연장이다.

## 예시 코드

```jsx
// frontend/src/App.jsx — UI에서 버튼을 숨기는 건 UX일 뿐, 보안 경계가 아니다
{loggedIn ? (
  <Link to="/posts/new">글쓰기</Link>
) : (
  <Link to="/login">로그인</Link>
)}
```

```java
// backend-spring — 진짜 경계는 여기, 프런트가 무엇을 보여주든 이 검사를 통과 못 하면 막힌다
@RequireAdmin
@PostMapping
public ResponseEntity<ApiResponse<PostResponse>> create(@RequestBody PostRequest request) { ... }
```

## 실무

실무에서도 프런트엔드 코드 자체를 "비밀"로 취급하지 않는 게 표준이다 — 대신 (1) 프런트에 비밀값을
절대 넣지 않는 빌드 파이프라인 규칙(예: CI에서 `.env` 파일의 `VITE_`/`NEXT_PUBLIC_` 접두사가
아닌 변수가 클라이언트 번들에 섞이면 실패시키는 린트), (2) 프로덕션 소스맵은 별도의 비공개
오류 추적 서비스(Sentry 등)에만 업로드하고 공개 배포본에는 포함하지 않기, (3) 모든 쓰기/민감
읽기 API에 서버 쪽 인가 검사를 두는 것이 조합된다. 난독화 도구(Terser의 mangle 옵션, 별도
obfuscator)를 아예 안 쓰는 팀도 많고, 쓰더라도 "약간의 시간 지연" 이상의 기대는 하지 않는다.

## 같이 보기

- [SQL Injection](./SQL-Injection.md) — 같은 시니어 리뷰에서 함께 나온 서버 쪽 보안 주제
- [Token Storage](./Token-Storage.md) — 관리자 토큰을 `localStorage`에 두는 선택과 그 트레이드오프
- [CORS](./CORS.md) — 프런트-백엔드 간 신뢰 경계를 다루는 또 다른 축

## 참고자료

- [OWASP — Client-Side Security](https://cheatsheetseries.owasp.org/cheatsheets/Securing_Cascading_Style_Sheets_Cheat_Sheet.html)
- [Kerckhoffs's principle (Wikipedia)](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle)
- [Vite — Build Options (`build.sourcemap`)](https://vite.dev/config/build-options.html#build-sourcemap)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 시니어 백엔드 리뷰에서 "F12로 JS가 노출된다"는 지적을 받고 정리 |
