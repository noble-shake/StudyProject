# Rate Limiting — 같은 요청을 얼마나 자주 허용할지 정하기

---

- **카테고리**: 네트워크/보안, 웹 개발
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

2026-09-08, 실제 배포된 `rotten-noble.com`을 대상으로 스캔/프로빙 활동이 있었다(핑, 코드 구조
탐색, SQL 인젝션 시도). 인젝션은 기존 prepared statement 덕에 실패했지만, 로그인 엔드포인트에
요청 횟수 제한이 전혀 없어 무차별 대입이나 단순 DoS에는 그대로 열려 있다는 게 드러났다. 이 문서는
그 대응으로 `backend/lib/rate_limit.php`를 만들면서 정리한 것이다.

## 정의

Rate limiting은 "같은 클라이언트(보통 IP나 계정, 토큰 단위)가 정해진 시간 창 안에 특정 요청을
몇 번까지 보낼 수 있는지"를 서버가 직접 세어서 제한하는 기법이다. 인증(누구인지 확인)이나
인가(무엇을 할 수 있는지 확인)와는 다른 축이다 — 정당한 자격을 가진 사용자라도 "너무 자주"
요청하면 막는다는 점이 핵심이다.

## 요약

Rate limiting은 "이 요청이 유효한가"가 아니라 "이 요청이 너무 잦은가"를 본다. 카운터를 어디에
두느냐(메모리 vs 공유 저장소)와 어떤 알고리즘으로 세느냐(고정 창 vs 슬라이딩 윈도우 vs 토큰
버킷)에 따라 정확도와 구현 난이도가 갈린다.

## 상세

### 왜 인증만으로는 부족한가

로그인 엔드포인트(`login.php`)는 아이디/비밀번호가 틀리면 401을 반환한다 — 이건 인증 실패를
정확히 처리하는 것이지, "시도 횟수"를 세는 것과는 무관하다. 공격자는 초당 수백 번씩 비밀번호를
바꿔가며 요청을 보낼 수 있고, 서버는 매번 성실하게 "틀렸습니다"라고 답하며 CPU(`password_verify`는
의도적으로 느리게 설계된 bcrypt를 쓴다)와 네트워크 대역폭을 소모한다. 즉 인증 로직 자체는 이미
올바르게 동작하고 있어도, 그 앞에 "이 IP가 최근 몇 번 시도했는가"를 세는 계층이 없으면 서버가
공짜로 무차별 대입 공격 상대를 해주는 꼴이 된다.

### 카운터를 어디에 두나 — 메모리 vs Redis

PHP는 요청마다 새 프로세스(또는 요청 단위로 초기화되는 워커)로 실행되기 때문에, 일반 변수나
정적 배열에 카운터를 두면 다음 요청이 왔을 때 이미 사라지고 없다. 카운트가 요청 간에 살아남으려면
요청 밖의 공유 저장소가 필요하다 — `RottenNoble-Project`는 이미 관리자 세션에 Redis를 쓰고
있으므로([[jwt-vs-redis-session]] 참고) 같은 인스턴스를 그대로 재사용했다.

```php
// backend/lib/rate_limit.php
function rate_limit_check(string $bucket, int $maxRequests, int $windowSeconds): void
{
    $key = 'rate_limit:' . $bucket . ':' . client_ip();

    $redis = redis_connect();
    $count = $redis->incr($key);
    if ($count === 1) {
        $redis->expire($key, $windowSeconds);
    }

    if ($count > $maxRequests) {
        send_error('요청이 너무 많습니다. 잠시 후 다시 시도하세요.', 429);
    }
}
```

`INCR`은 Redis가 원자적으로 처리하는 명령이다 — "GET으로 현재 값을 읽고 +1해서 SET한다"를
애플리케이션 코드에서 직접 하면, 동시에 두 요청이 들어왔을 때 둘 다 같은 값을 읽고 둘 다 같은
값으로 SET해버리는 경쟁 상태(race condition)가 생긴다. `INCR`은 이 read-modify-write를 Redis
서버 안에서 한 번에 처리하므로 이 문제가 없다.

키가 새로 생긴 시점(`$count === 1`)에만 `EXPIRE`를 걸어 시간 창을 설정한다 — 이게 "고정 창(fixed
window)" 방식이다. 창이 시작된 시점부터 `$windowSeconds`가 지나면 Redis가 키를 자동으로 지워서
카운터가 0으로 리셋된다.

### 왜 Redis 연결 실패 시 그냥 통과시키나

```php
try {
    $redis = redis_connect();
    // ...
} catch (Throwable $e) {
    return; // 제한 없이 통과
}
```

이건 "실패를 무시하는 안일한 코드"처럼 보일 수 있지만 의도적인 선택이다. Redis가 잠깐
내려갔다고 해서 로그인이나 방명록 작성 자체가 막히면, rate limiting이라는 부가 기능이 핵심
기능의 가용성을 해치는 역설적인 상황이 된다. 보안 기능을 추가할 때는 "이 기능이 실패하면 무엇이
더 나쁜가"를 먼저 판단해야 한다 — 여기서는 "가끔 rate limit이 안 걸리는 것"이 "Redis 한 번 흔들릴
때마다 사이트가 로그인 불가 상태가 되는 것"보다 훨씬 낫다.

### 고정 창의 한계

고정 창 방식은 구현이 간단하지만 "창 경계에서의 버스트"에 약하다. 예를 들어 5분 창에 5회
제한이라면, 공격자가 4분 59초에 5번, 5분 1초(다음 창 시작 직후)에 또 5번을 보내면 사실상
10초 안에 10번을 통과시켜준 셈이다. 이보다 정교한 방식(슬라이딩 윈도우, 토큰 버킷)은 이 문제를
줄이지만 구현이 더 복잡하다 — 개인 포트폴리오 규모에서는 고정 창의 단순함과 이 정도 허점을
맞바꿀 만하다고 판단했다.

## 비교표

| 방식 | 정확도 | 구현 난이도 | 이 프로젝트의 선택 |
|---|---|---|---|
| 고정 창(fixed window) | 창 경계 버스트에 약함 | 낮음(INCR+EXPIRE 두 줄) | 사용 중 |
| 슬라이딩 윈도우(sliding window log) | 정확함 | 중간(타임스탬프 목록 관리 필요) | 미사용 |
| 토큰 버킷(token bucket) | 순간 버스트를 일부 허용하면서도 평균은 제한 | 중간~높음 | 미사용 |

## 질문

- **Q. IP 기반 제한이면 같은 공유기를 쓰는 여러 사용자가 서로 영향을 주지 않나?**
  A. 맞다 — 카페나 회사처럼 NAT 뒤에서 IP를 공유하는 환경이면, 한 명이 제한에 걸리면 같은
  공인 IP를 쓰는 다른 사람도 영향을 받는다. 로그인처럼 "계정"이 특정되는 요청은 IP와 계정 ID를
  같이 묶어 제한하면 이 문제를 줄일 수 있지만, `RottenNoble-Project`는 관리자가 1명뿐이라 계정
  단위로 나눌 실익이 없어 IP 단위로만 두었다.

- **Q. 진짜 분산 서비스 거부 공격(여러 IP에서 동시에)도 이걸로 막을 수 있나?**
  A. 아니다. IP당 제한은 "한 IP가 혼자 너무 자주 요청하는 것"만 막는다. 수백~수천 개의 서로 다른
  IP에서 동시에 소량씩 요청이 오면 각 IP는 제한에 안 걸리면서 서버 전체는 부하를 받을 수 있다.
  이건 애플리케이션 코드가 아니라 CDN/WAF(예: Cloudflare) 같은 앞단 인프라가 처리할 영역이다 —
  rate limiting과 WAF는 같은 문제의 다른 층을 담당한다.

## 예시 코드

```php
// login.php에 적용한 실제 위치 — CORS/메서드 검사 다음, 비밀번호 확인 전
allow_cors(['POST']);
if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    send_error('POST만 허용됩니다.', 405);
}

rate_limit_check('login', 5, 300); // IP당 5분에 5회

$body = json_decode(file_get_contents('php://input'), true);
// ... 비밀번호 확인은 이 다음
```

성공/실패 여부와 무관하게 요청이 들어온 시점에 카운트한다 — "실패한 시도만 센다"고 하면
공격자가 항상 성공하는 요청(예: 이미 아는 계정으로 로그인)을 반복해서 다른 목적(DoS)으로
악용할 여지가 남기 때문이다.

## 플로우차트

`Rate-Limiting.flow.md` 참고 — 요청이 들어와서 허용/차단으로 갈리는 전체 흐름.

## 실무

실무에서는 애플리케이션 코드에 직접 rate limiting을 넣기보다, API 게이트웨이(Kong, AWS API
Gateway)나 리버스 프록시(Nginx `limit_req`, Cloudflare Rate Limiting) 계층에서 처리하는 경우가
많다 — 요청이 애플리케이션 서버(여기서는 PHP-FPM/Apache)에 도달하기도 전에 걸러낼 수 있어서
더 효율적이고, 여러 서비스에 동일한 정책을 일관되게 적용하기도 쉽다. `RottenNoble-Project`는
그런 앞단 인프라가 없는 개인 NAS 배포라 애플리케이션 레벨(PHP+Redis)에서 직접 구현했다 — 이후
Cloudflare 같은 프록시를 앞에 두게 되면, 거기서도 한 번 더 제한을 걸어 이중 방어선을 만드는 게
자연스러운 다음 단계다.

## 같이 보기

- [Redis](../Infrastructure/Redis.md) — 이 프로젝트가 이미 세션 저장에 쓰던 Redis를 rate limit
  카운터 저장소로도 재사용한 배경
- [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) — 같은 Redis 인스턴스를 세션에 쓰는
  이유
- [CORS](./CORS.md) — 같은 날 함께 손본 또 다른 방어 심층화 항목

## 참고자료

- [Redis INCR 명령 문서](https://redis.io/docs/latest/commands/incr/)
- [Cloudflare — Rate limiting이란](https://www.cloudflare.com/learning/bots/what-is-rate-limiting/)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 실제 스캔/프로빙 대응으로 로그인·방명록·관리자 쓰기 엔드포인트에 rate limiting 도입 |
