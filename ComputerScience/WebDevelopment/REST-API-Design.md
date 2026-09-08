# REST 스타일 API 설계 (응답 봉투 패턴)

---

**카테고리**: 웹 개발, 네트워크
**상태**: 완료
**기준 시점**: 2026-09-08
**관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 2~3회차(아키텍처 계층, 프런트-백엔드
통신) 코드 학습에서 나온 주제.

## 정의

REST(REpresentational State Transfer)는 웹 API를 설계할 때 흔히 따르는 관례의 모음이다 — "자원
(resource)을 URL로 표현하고, HTTP 메서드(GET/POST/PUT/DELETE)로 그 자원에 대해 무엇을 할지
표현한다"는 게 핵심 아이디어다. "응답 봉투(envelope)"는 그 위에 얹는 또 다른 관례로, 모든 API
응답을 `{status: ..., data: ...}` 같은 일관된 형태로 감싸서, 클라이언트가 매번 같은 방식으로
성공/실패를 판단할 수 있게 하는 패턴이다.

## 요약

이 프로젝트의 모든 백엔드 엔드포인트는 정확히 같은 두 가지 응답 모양(`{status:'ok', data}` /
`{status:'error', message}`)만 쓰고, 프런트엔드는 그 모양 하나만 알면 모든 API를 다룰 수 있다 —
작은 규모지만 "일관성"이라는 REST API 설계의 핵심 가치를 제대로 지키고 있는 사례다.

## 상세

### 이 프로젝트가 실제로 쓰는 봉투 형식

```php
// backend/response.php
function send_json($data, int $httpCode = 200): void
{
    http_response_code($httpCode);
    echo json_encode(['status' => 'ok', 'data' => $data]);
    exit;
}

function send_error(string $message, int $httpCode = 400): void
{
    http_response_code($httpCode);
    echo json_encode(['status' => 'error', 'message' => $message]);
    exit;
}
```

성공이면 `data` 필드 안에 실제 값(글 목록, 새로 만든 글 정보 등)이 들어가고, 실패면 `message`
필드에 사람이 읽을 수 있는 에러 메시지가 들어간다. 이 프로젝트의 모든 엔드포인트가 예외 없이 이
두 함수 중 하나로만 응답한다 — 그래서 프런트엔드의 `request()` 헬퍼(`frontend/src/api/posts.js`)가
`body.status !== 'ok'`인지만 확인하면, 어떤 엔드포인트를 호출했든 실패를 똑같은 방식으로 잡아낼
수 있다.

### HTTP 상태 코드도 같이 쓴다는 것

봉투 안의 `status` 필드와는 별개로, 이 프로젝트는 실제 HTTP 상태 코드도 의미에 맞게 구분해서
쓴다:

| 상태 코드 | 쓰이는 곳 | 의미 |
|---|---|---|
| 200 | 조회 성공(`get_posts.php` 등 기본값) | 정상 처리 |
| 201 | `create_post.php` 성공 | 새 자원이 생성됨 |
| 204 | CORS 프리플라이트 응답 | 내용 없이 성공 |
| 400 | 잘못된 입력(`id` 누락, 제목 길이 초과 등) | 클라이언트 요청 자체가 잘못됨 |
| 401 | 로그인 필요/세션 무효 | 인증 실패 |
| 404 | 존재하지 않는 글 조회 | 자원 없음 |
| 405 | 잘못된 HTTP 메서드(POST 엔드포인트에 GET 요청 등) | 메서드 허용 안 됨 |
| 500 | Redis 연결 실패 등 서버 내부 오류 | 서버 오류 |

**왜 봉투의 `status` 필드가 있는데 HTTP 코드도 따로 신경 쓰나?** 이 둘은 서로 다른 계층의 정보다.
HTTP 상태 코드는 브라우저, 프록시, 로그 수집기처럼 **응답 본문(JSON)을 파싱하지 않는 도구들**도
바로 이해할 수 있는 신호다 — 예를 들어 브라우저 개발자 도구의 네트워크 탭에서 실패한 요청이
빨간색으로 표시되는 것도, CDN이나 모니터링 도구가 에러율을 집계하는 것도 이 코드를 본다. 봉투의
`status`/`message`는 반대로 애플리케이션 코드(자바스크립트)가 실제로 무엇이 잘못됐는지 사람이 읽을
문장으로 알아야 할 때 쓰인다. 둘 다 있어야 각자의 소비자에게 맞는 정보를 줄 수 있다.

### 왜 봉투 패턴을 쓰는가 (안 쓰면 어떻게 되나)

봉투 없이 그냥 데이터를 그대로 반환하는 API도 많다 — 예를 들어 `get_posts.php`가
`{status:'ok', data:[...]}`가 아니라 그냥 `[...]`(배열 그대로)를 반환할 수도 있었다. 문제는
에러가 났을 때다. 봉투가 없으면 "이 응답이 성공인지 실패인지"를 HTTP 상태 코드에만 의존해서
판단해야 하는데, 네트워크 장애나 프록시 설정에 따라 상태 코드가 애매해지는 경우가 실무에서
종종 있다. 봉투 패턴은 응답 본문 자체에 성공/실패 표시를 이중으로 남겨서, 이런 애매한 상황에서도
클라이언트가 명확하게 판단할 수 있게 해준다.

## 비교표

| 방식 | 성공/실패 판단 근거 | 이 프로젝트 사용 여부 |
|---|---|---|
| 봉투 없이 데이터 그대로 반환 | HTTP 상태 코드에만 의존 | 사용 안 함 |
| `{status, data\|message}` 봉투(이 프로젝트) | HTTP 코드 + 본문의 `status` 필드, 이중 확인 | **사용 중** |
| GraphQL 스타일(`{data, errors}`) | 항상 200을 반환하고 `errors` 배열 유무로 판단 | 사용 안 함(REST/JSON 방식) |
| JSON:API 표준(`{data, errors, meta}` 등 세분화) | 표준화된 필드 구조 | 사용 안 함(자체 최소 규격) |

## 질문

- **Q. 이 프로젝트의 봉투 형식은 업계 표준(JSON:API 등)을 따른 건가?**
  A. 아니다. `{status, data}` / `{status, message}`는 이 프로젝트가 자체적으로 정한 최소한의
  규칙이다. JSON:API 같은 정식 표준은 페이지네이션, 관계(relationship) 표현 등 훨씬 세분화된
  규격을 갖고 있는데, 이 프로젝트 규모(엔드포인트 10여 개, 글/방명록 두 종류 자원)에서는 그런
  규격이 과하다 — "일관성만 지키면 충분하다"는 판단으로 자체 최소 규격을 쓴 것으로 보인다.

- **Q. 페이지네이션(목록을 나눠서 가져오기)은 어떻게 처리하나?**
  A. `get_posts.php`를 보면 현재는 페이지네이션이 없다 — 전체 글을 한 번에 다 가져온다. 글
  개수가 아주 많아지면 이 부분이 먼저 손봐야 할 지점이 될 것이다(응답 봉투 안에 `data`와 별도로
  `meta: {page, totalCount}` 같은 필드를 추가하는 식으로 확장 가능).

## 예시 코드

```json
// 성공 응답 (get_post.php?id=3)
{
  "status": "ok",
  "data": { "id": 3, "title": "...", "content": "...", "created_at": "..." }
}
```

```json
// 실패 응답 (같은 엔드포인트, 존재하지 않는 id)
{
  "status": "error",
  "message": "게시글을 찾을 수 없습니다."
}
```

```js
// frontend/src/api/posts.js — 이 봉투를 소비하는 프런트 쪽 코드
async function request(path, options = {}) {
  const res = await fetch(`${API_BASE_URL}${path}`, options);
  const body = await res.json();
  if (body.status !== 'ok') {
    throw new Error(body.message || '요청에 실패했습니다.');
  }
  return body.data;
}
```

## 플로우차트

(생략 — 봉투 형식은 "응답 하나의 모양"에 대한 규약이라 순서나 분기가 없다. 표로 이미 충분하다.)

## 실무

실무에서는 이 프로젝트처럼 자체적인 최소 봉투 규격을 쓰는 팀도 많고, JSON:API나 OpenAPI 스펙을
엄격히 따르는 팀도 있다 — 조직 규모와 API 소비자 수에 따라 갈린다. 외부에 공개하는 API일수록
표준 규격을 따르는 게 문서화·클라이언트 SDK 자동 생성 등에서 유리하고, 이 프로젝트처럼 프런트-백엔드
를 같은 사람(팀)이 관리하는 내부용 API는 최소 규격으로도 충분한 경우가 많다. 최근 동향으로는
GraphQL이나 tRPC(TypeScript 풀스택 환경)처럼 "REST + 봉투"라는 관례 자체를 다른 방식으로
대체하려는 흐름도 있지만, REST + JSON 봉투는 여전히 가장 보편적인 선택지다.

## 같이 보기

- [PHP](./PHP.md) — 이 봉투를 만드는 `response.php`가 속한 언어/구조
- [CORS](../Network/CORS.md) — 같은 `response.php`가 담당하는 또 다른 공통 관심사

## 참고자료

- [MDN — HTTP 응답 상태 코드](https://developer.mozilla.org/ko/docs/Web/HTTP/Status)
- [JSON:API 명세](https://jsonapi.org/) (참고용 — 이 프로젝트가 따르는 표준은 아님)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 2~3회차 학습에서 반복 확인한 응답 패턴을 독립 주제로 정리 |
