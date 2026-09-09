# CORS (Cross-Origin Resource Sharing)

---

- **카테고리**: 웹 개발, 네트워크/보안
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 3회차(프런트-백엔드 통신)에서 발견한
문서-코드 불일치(`MEMO-WEB-02`)를 계기로 CORS 자체를 별도 주제로 분리.

## 정의

브라우저는 기본적으로 "같은 origin(같은 프로토콜+도메인+포트)에서 온 요청만 자유롭게 허용"하는
**동일 출처 정책(Same-Origin Policy)**을 따른다. `https://rotten-noble.com`에서 실행되는
자바스크립트가 `https://api.other-site.com`으로 요청을 보내려 하면, 브라우저가 기본적으로 그
응답을 자바스크립트가 읽지 못하게 막는다. CORS는 서버가 "이 origin에서 오는 요청은 허용한다"고
응답 헤더로 명시적으로 선언해서, 이 기본 차단을 **의도적으로 풀어주는** 메커니즘이다.

## 요약

CORS는 "다른 사이트의 공격을 막는 방화벽"이 아니라 "브라우저가 기본으로 막아둔 것을 서버가 골라서
풀어주는 허가증"이다 — 이 구분을 놓치면 와일드카드(`*`)가 왜 위험할 수 있는지 이해하기 어렵다.

## 상세

### 왜 브라우저가 이런 걸 막아두나

만약 이 정책이 없다면, 사용자가 은행 사이트에 로그인한 상태로 악성 사이트를 방문했을 때, 그
악성 사이트의 자바스크립트가 사용자 몰래 은행 사이트에 요청을 보내고 그 응답(계좌 정보 등)을
읽어갈 수 있다. 브라우저는 쿠키 같은 인증 정보를 origin과 무관하게 자동으로 요청에 실어 보내기
때문에, 이런 요청은 사용자가 로그인한 상태 그대로 나간다 — 그래서 "응답을 읽는 것"만이라도
막아야 한다.

### `RottenNoble-Project`가 CORS를 다루는 방식

이 프로젝트는 개발 환경에서 프런트(`localhost:3000`)와 백엔드(`localhost`, Apache 80번)가 서로
다른 포트라 이미 다른 origin이었다. 그래서 백엔드 모든 엔드포인트가 `response.php`의
`allow_cors()` 함수를 거친다:

```php
// backend/response.php
function allow_cors(array $methods = ['GET']): void
{
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Methods: ' . implode(', ', $methods) . ', OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type');

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}
```

세 가지 일이 여기서 일어난다.

1. **`Access-Control-Allow-Origin: *`** — "어떤 origin에서 온 요청이든 이 응답을 읽어도 된다"는
   선언. 와일드카드(`*`)는 "모든 origin 허용"을 뜻한다.
2. **`Access-Control-Allow-Methods`/`Allow-Headers`** — 어떤 HTTP 메서드와 헤더를 쓸 수 있는지
   알려준다.
3. **`OPTIONS` 프리플라이트 처리** — `Content-Type: application/json`처럼 "단순 요청"의 조건을
   벗어나는 요청을 보내기 전에, 브라우저는 먼저 `OPTIONS` 메서드로 "이 요청 보내도 되냐"고 서버에
   먼저 물어본다(프리플라이트). 서버가 204(내용 없음)로 답하며 위 헤더들을 실어 보내면, 브라우저가
   그제서야 실제 요청을 보낸다.

### 발견한 문제 — 문서화된 결정과 실제 코드가 갈라진 지점

`CODE_MEMO.md`의 `MEMO-WEB-02`는 이 와일드카드를 처음 붙일 때(공개 GET 엔드포인트 대상) 이렇게
명시적으로 경고해뒀다:

> "관리자 글쓰기/수정 같은 인증 붙는 엔드포인트를 추가할 때 이 와일드카드를 그대로 복사하면 안
> 된다 — 그때는 쿠키/토큰이 오가므로 명시적 origin 허용목록으로 바꿔야 한다."

하지만 실제로는 `login.php`, `create_post.php`, `update_post.php`, `delete_post.php`가 전부
공유 함수 `allow_cors()`를 그대로 호출해서, 경고했던 그 와일드카드를 그대로 쓰고 있다.

### 왜 지금 당장 위험하지 않은가 — 쿠키 vs 헤더 토큰의 차이

여기서 CORS를 제대로 이해하려면 한 가지를 짚어야 한다. **CORS 응답 헤더는 "요청을 막는 것"이
아니라 "응답을 읽는 것을 막는 것"**이다. 즉, `evil.com`의 스크립트가 이 프로젝트의
`create_post.php`에 요청을 보내는 것 자체는 CORS와 무관하게 가능하다 — 문제는 "그 요청이 실제로
인증된 상태로 처리되는가"다.

- **쿠키 기반 인증이었다면**: 브라우저는 쿠키를 origin과 무관하게 자동으로 실어 보낸다. 사용자가
  관리자로 로그인한 상태에서 `evil.com`을 열기만 해도, 그 페이지의 스크립트가 보낸 요청에 관리자
  쿠키가 자동으로 따라붙어 서버가 진짜 관리자 요청으로 착각한다 — 이게 CSRF(Cross-Site Request
  Forgery)다. 이 경우 와일드카드 CORS는 공격자가 응답까지 읽을 수 있게 해줘서 피해를 키운다.
- **이 프로젝트처럼 `Authorization: Bearer {token}` 헤더 기반이라면**: 브라우저는 이 헤더를 절대
  자동으로 붙여주지 않는다. `evil.com`의 스크립트가 토큰 값 자체를 모르면(다른 origin의
  `localStorage`는 읽을 수 없다) 애초에 유효한 요청을 만들 수조차 없다. 그래서 와일드카드가
  남아있어도 클래식 CSRF 경로 자체가 막혀 있다.

**다만** 이건 "설계자가 CORS까지 고려해서 헤더 토큰을 선택했다"는 뜻은 아니다 — `MEMO-WEB-04`를
보면 헤더 토큰을 고른 이유는 어디까지나 기존 인프라(Redis 세션)와의 일관성이었고, CORS와의
상호작용은 별도로 언급되지 않는다. 결과적으로 안전한 조합이 된 것이지, 그렇게 설계된 것은 아니라는
차이를 구분해서 봐야 한다.

## 비교표

| 항목 | 와일드카드(`*`) | 명시적 origin 허용목록 |
|---|---|---|
| 설정 난이도 | 매우 쉬움 | origin이 바뀔 때마다 코드 수정 필요 |
| 쿠키 기반 인증과 함께 쓸 때 | 위험(CSRF 응답 탈취 가능) | 안전(허용된 origin만 응답 읽기 가능) |
| 헤더 토큰 기반 인증과 함께 쓸 때 | 상대적으로 안전(토큰을 몰라서 못 뚫음) | 더 안전(방어선이 하나 더 있음) |
| 이 프로젝트의 현재 상태(~2026-09-09) | PHP 시절엔 전체 엔드포인트에 적용 중이었고, 실제 배포된 Spring Boot 백엔드도 다시 와일드카드다 — 아래 "2026-09-09 갱신" 참고 | PHP용 패치(PR #2)가 이 방향으로 준비됐으나 **머지 없이 close됨** — 실제 배포된 코드엔 반영된 적 없음 |

## 질문

- **Q. `credentials: 'include'`(쿠키 포함 요청)와 와일드카드를 같이 쓸 수 있나?**
  A. 아니다. 브라우저 스펙 자체가 이걸 막는다 — `Access-Control-Allow-Origin: *`와
  `Access-Control-Allow-Credentials: true`를 동시에 쓰는 응답은 브라우저가 거부한다. 쿠키를
  쓰려면 반드시 구체적인 origin을 명시해야 한다. 이 프로젝트가 애초에 쿠키가 아니라 헤더 토큰을
  썼기 때문에 이 제약 자체를 마주칠 일이 없었다.

- **Q. `OPTIONS` 프리플라이트는 왜 모든 요청에 안 일어나나?**
  A. `GET`/`POST`이면서 `Content-Type`이 `application/x-www-form-urlencoded` 등 특정 조건을
  만족하는 "단순 요청"은 프리플라이트 없이 바로 나간다. 이 프로젝트는 `Content-Type:
  application/json`을 쓰는 POST 요청이 많아서(단순 요청 조건을 벗어남) 프리플라이트가 실제로
  발생한다 — `allow_cors()`가 `OPTIONS`를 별도로 처리해두지 않았다면 이 요청들이 전부 실패했을
  것이다.

## 예시 코드

```
// 브라우저가 실제로 보내는 프리플라이트 요청 (create_post.php 호출 전)
OPTIONS /backend/create_post.php HTTP/1.1
Origin: https://rotten-noble.com
Access-Control-Request-Method: POST
Access-Control-Request-Headers: content-type, authorization
```

```php
// 서버가 응답해야 하는 헤더 (2026-09-08 이전 allow_cors()가 실제로 만들던 것 — 지금은 아래 참고)
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type
HTTP/1.1 204 No Content
```

```php
// 2026-09-08 이후 — 요청 Origin이 허용목록에 있을 때만 그 origin을 그대로 반사한다
Access-Control-Allow-Origin: https://rotten-noble.com
Vary: Origin
Access-Control-Allow-Methods: POST, OPTIONS
Access-Control-Allow-Headers: Content-Type, Authorization
HTTP/1.1 204 No Content
```

## 플로우차트

(생략 — "요청 전에 프리플라이트가 한 번 더 오간다"는 흐름은 위 예시 코드 두 블록의 순서로 이미
충분히 전달된다.)

## 실무

실무에서는 프로덕션 API에 와일드카드를 그대로 쓰는 경우는 드물다 — 대부분 프런트엔드가 배포된
실제 도메인만 허용목록에 넣는다. 다만 이 프로젝트처럼 "인증 방식이 쿠키가 아니라 헤더/토큰
기반"이라면 실무에서도 와일드카드를 잠정적으로 허용하는 경우가 있다(공개 API, 여러 클라이언트가
있는 서비스 등). 중요한 건 "쿠키를 쓰는 순간부터는 와일드카드를 쓸 수 없다"는 걸 기억하는 것 —
나중에 이 프로젝트가 인증 방식을 쿠키 기반으로 바꾼다면, 이 와일드카드는 반드시 먼저 손봐야 한다.

(2026-09-08 갱신) 실제로는 인증 방식을 안 바꾼 상태에서도 방어 심층화 차원에서 먼저 손보려 했다 —
CSRF 경로가 원래 안전했다는 판단은 여전히 유효하지만, 스캐너가 이것저것 찔러보는 걸 실제로
본 뒤로는 "지금 당장 위험하지 않다"와 "고칠 필요가 없다"는 다른 문제라고 판단했다.

**(2026-09-09 갱신) 그 판단이 뒤집혔다 — 하지만 배포는 안 됐다.** 위 허용목록 패치는 실제로
PHP `backend/` 위에서 PR #2로 준비까지 됐지만, 그 PR이 머지 없이 close되고 백엔드 자체가 Spring
Boot로 재작성되면서 반영될 기회가 사라졌다. 그리고 새로 작성·**프로덕션에 배포된** Spring
`WebConfig.java`는 명시적으로 다시 `allowedOrigins("*")`를 선택했다 — 코드 주석은 이유를 이렇게
남긴다: "인증이 쿠키가 아니라 `Authorization: Bearer` 헤더 방식이라 CORS 자격증명 문제가 없다."
이건 위 "쿠키 vs 헤더 토큰" 절의 논리와 정확히 같은 근거다 — 즉 **처음부터 이 프로젝트에선
와일드카드가 구조적으로 안전했다는 분석 자체는 맞았고, 허용목록으로 좁힌 건 방어 심층화였을
뿐 필수는 아니었다는 뜻으로 읽을 수 있다.** 다만 이 결정이 "재검토해서 유지"가 아니라 "패치가
반영될 기회를 놓치고 원상태로 돌아간" 우연에 가까운 경로로 벌어졌다는 게 배울 점이다 — 보안
결정은 코드가 바뀔 때마다 다시 증발할 수 있으니, 한 번 고쳤다고 그 상태가 계속 유지된다고
가정하면 안 된다.

## 같이 보기

- [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) — 이 프로젝트가 쿠키 대신 헤더 토큰을 쓰게 된 배경
- [Token Storage (localStorage vs Cookie)](../Security/Token-Storage.md) — 토큰을 어디에 저장하느냐가
  CORS/CSRF 위험도에 미치는 영향
- [Rate Limiting](../Security/Rate-Limiting.md) — 같은 날 함께 손본 또 다른 방어 심층화 항목

## 참고자료

- [MDN — CORS](https://developer.mozilla.org/ko/docs/Web/HTTP/CORS)
- `DevelopPrompt/CurrentProject/_RottenNobleProject/CODE_MEMO.md`의 `MEMO-WEB-02`

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 3회차 학습에서 발견한 CORS 와일드카드 드리프트를 독립 주제로 정리 |
| 2026-09-08 | 와일드카드 → 명시적 origin 허용목록으로 실제 수정 (PHP `backend/` 기준) | 사이트가 스캔/프로빙을 당한 뒤 방어 심층화로 `MEMO-WEB-02` 경고 항목을 실제로 해소 |
| 2026-09-09 | 위 패치는 머지 안 됨, 실제 배포된 Spring Boot 백엔드는 와일드카드로 되돌아감 — "쿠키 vs 헤더 토큰" 논리를 근거로 명시 | 백엔드가 PHP → Spring Boot로 재작성되며 PR #2가 반영될 기회 없이 close됨 |
