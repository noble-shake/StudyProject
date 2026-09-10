# Redis

---

- **카테고리**: 웹 개발, 인프라
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project` (`RottenNoble-HttpServer`, `RottenNoble-TCPServer`와 인스턴스 공유)
- **엔진**: `Web`
- **상위 문서**: -

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 2~3회차(아키텍처 계층, 인증 흐름)에서
나온 주제. `STUDY-01`(JWT vs Redis 세션)의 배경 지식이기도 하다.

## 정의

Redis는 데이터를 디스크가 아니라 메모리에 저장하는 key-value 데이터베이스다. "메모리에 저장한다"는
말은 곧 "읽고 쓰는 속도가 매우 빠르지만, 서버가 꺼지면 기본적으로 데이터가 사라질 수 있다"는 뜻이다
(디스크에 스냅샷을 남기는 옵션도 있지만, 이 프로젝트는 그런 영속성이 필요 없는 데이터에만 Redis를
쓴다). MariaDB 같은 관계형 DB가 "오래 보관해야 하는 구조화된 데이터"를 위한 것이라면, Redis는
"잠깐 있다가 사라져도 되는 데이터, 혹은 아주 빠르게 조회해야 하는 데이터"를 위한 도구다.

## 요약

RottenNobleProject는 관리자 로그인 세션 토큰 하나를 저장하는 데만 Redis를 쓴다 — DB에 영구 저장할
필요는 없지만(하루 지나면 자동으로 사라져야 함) 매 요청마다 빠르게 확인해야 하는 데이터라, 이
프로젝트가 가진 두 가지 저장소(MariaDB, Redis)의 역할이 정확히 나뉘어 있다.

## 상세

### 왜 세션을 MariaDB가 아니라 Redis에 두나

세션 토큰을 MariaDB의 `sessions` 테이블 같은 곳에 저장할 수도 있었다. 하지만 그렇게 하면 두 가지가
아쉬워진다. 첫째, 만료 처리를 직접 짜야 한다 — "24시간 지난 row는 지운다"는 로직을 크론잡이나
별도 코드로 돌려야 한다. 둘째, 로그인 여부 확인이라는 아주 잦은 작업(글쓰기 페이지에 들어갈 때마다,
글을 저장할 때마다)에 매번 관계형 DB 조회가 끼어든다.

Redis는 이 두 문제를 기본 기능으로 해결해준다. `SET key value EX 86400`처럼 값을 저장할 때 만료
시간(TTL, Time To Live)을 같이 지정하면, Redis가 알아서 그 시간이 지난 키를 지워준다 — 별도의
정리 코드가 필요 없다. 그리고 메모리 기반이라 조회 속도가 디스크 기반 DB보다 훨씬 빠르다.

```php
// backend/login.php — 실제 코드
$redis->set("admin_session:$token", 'admin', 86400); // 24시간 뒤 자동 삭제
```

### RESP 프로토콜을 직접 구현한 이유

보통 PHP에서 Redis를 쓰려면 `phpredis`라는 C 확장을 설치하거나, Composer로 `predis` 같은 라이브러리
패키지를 받는다. 이 프로젝트는 둘 다 쓰지 않고, `backend/lib/redis_client.php`에 최소한의 Redis
클라이언트를 직접 구현했다:

```php
// backend/lib/redis_client.php
private function command(array $args)
{
    $cmd = '*' . count($args) . "\r\n";
    foreach ($args as $arg) {
        $cmd .= '$' . strlen($arg) . "\r\n" . $arg . "\r\n";
    }
    fwrite($this->socket, $cmd);
    return $this->readReply();
}
```

이건 Redis가 클라이언트-서버 통신에 쓰는 **RESP(REdis Serialization Protocol)**라는 텍스트 기반
프로토콜을 그대로 손으로 구현한 것이다. `*2\r\n$3\r\nGET\r\n$3\r\nfoo\r\n`처럼, "배열 원소 몇
개인지"와 "각 문자열이 몇 바이트인지"를 프로토콜 자체에 미리 적어주는 방식이라 파싱이 비교적
단순하다 — 그래서 라이브러리 없이도 소켓 통신 코드 80줄 정도로 GET/SET/DEL을 구현할 수 있었다.

**왜 굳이 이렇게 했을까.** 주석에 답이 있다 — `RottenNoble-HttpServer`(Node.js)와
`RottenNoble-TCPServer`(C++, hiredis 라이브러리 사용)가 **완전히 같은 Redis 인스턴스**를, 완전히
같은 커맨드 패턴(`SET key value EX seconds` / `GET` / `DEL`)으로 공유한다. 세 개의 서로 다른 언어가
같은 저장소를 다루는 상황에서, PHP만 특정 라이브러리(`phpredis`나 `predis`)의 고유한 동작 방식에
의존하면, 그 라이브러리가 프로토콜을 미묘하게 다르게 다루는 경우(타임아웃 처리, 재연결 정책 등)
디버깅이 "이게 Redis 문제인지 라이브러리 문제인지" 구분하기 어려워질 수 있다. 프로토콜을 직접
구현하면 세 언어가 정확히 같은 저수준 동작을 하고 있다는 걸 코드로 보장할 수 있다.

## 비교표

| 항목 | Redis (이 프로젝트의 세션 저장) | MariaDB 세션 테이블 | PHP 기본 세션(`$_SESSION`, 파일 기반) |
|---|---|---|---|
| 저장 위치 | 메모리 | 디스크 | 서버 로컬 디스크(파일) |
| 자동 만료(TTL) | 기본 기능(`EX`) | 직접 구현 필요 | `session.gc_maxlifetime` 설정으로 가능하나 즉시 삭제는 아님 |
| 여러 서버(Node/C++/PHP)에서 공유 | 가능 (실제로 이렇게 쓰임) | 가능 | 어려움(파일이 서버 로컬에 묶임) |
| 조회 속도 | 매우 빠름(메모리) | 상대적으로 느림(디스크) | 빠름(로컬 파일) |

## 질문

- **Q. Redis에 저장된 걸 서버를 재시작하면 잃어버리지 않나?**
  A. 기본 설정으로는 그렇다. Redis는 옵션으로 디스크에 스냅샷(RDB)이나 변경 로그(AOF)를 남겨
  재시작 후 복구할 수도 있지만, 이 프로젝트의 세션 토큰처럼 "어차피 24시간 뒤엔 사라져야 하고,
  없어지면 그냥 다시 로그인하면 되는" 데이터에는 그런 영속성이 필요 없다 — 관리자 한 명만 쓰는
  개인 블로그라 세션이 날아가도 재로그인 한 번으로 끝난다.

- **Q. `phpredis`나 `predis`를 안 쓴 게 정말 합리적인 선택이었을까?**
  A. 트레이드오프가 있다. 직접 구현한 클라이언트는 GET/SET(EX)/DEL 세 개 명령만 지원하는데, 이
  프로젝트는 딱 그 세 개만 필요해서 지금은 문제가 없다. 하지만 나중에 Redis의 다른 기능(예:
  리스트, 트랜잭션, Pub/Sub)이 필요해지면 직접 구현을 계속 확장해야 하고, 그건 검증된 라이브러리를
  쓰는 것보다 버그가 생길 여지가 크다. "지금 필요한 것만 최소로 구현한다"는 선택이 지금 규모에는
  맞지만, 확장성과는 맞바꾼 결정이다.

## 예시 코드

```php
// backend/auth.php — 실제로 세션을 확인하는 코드
function require_admin(): void
{
    $header = get_authorization_header();
    if (!$header || !preg_match('/^Bearer\s+(.+)$/', $header, $m)) {
        send_error('로그인이 필요합니다.', 401);
    }
    $token = $m[1];

    $redis = redis_connect();
    $value = $redis->get("admin_session:$token");
    $redis->close();

    if ($value !== 'admin') {
        send_error('세션이 유효하지 않거나 만료되었습니다.', 401);
    }
}
```

`admin_session:{token}`이라는 키 이름 패턴 자체가 이미 하나의 관례다 — 콜론(`:`)으로 네임스페이스를
나누는 건 Redis 커뮤니티에서 흔히 쓰는 키 네이밍 방식이다.

## 플로우차트

로그인부터 보호된 요청까지, 시간 순서로 무슨 일이 일어나는지는 순서가 중요한 정보라 그림으로
남겨둔다.

→ [`Redis.flow.md`](./Redis.flow.md)

## 실무

실무에서 Redis는 세션 저장소 외에도 캐시(자주 조회되는 DB 쿼리 결과를 잠깐 저장), 실시간 랭킹
(Sorted Set), 메시지 큐(Pub/Sub이나 Streams), 분산 락 등 아주 다양하게 쓰인다. "세션 하나만 위해
Redis를 새로 띄운다"는 이 프로젝트의 쓰임새는 실무 기준으로는 다소 미니멀한 편이지만, 세 개의 다른
언어 서버가 같은 인증 상태를 공유해야 하는 시나리오 자체는 마이크로서비스 환경에서 실제로 자주
나오는 요구사항이다. 실무에서는 대부분 `phpredis`(성능 우선) 또는 Predis(설치가 쉬움) 같은 검증된
라이브러리를 쓰고, RESP 프로토콜을 직접 구현하는 경우는 거의 없다 — 이 프로젝트처럼 "여러 언어가
프로토콜 차이 없이 완전히 동일하게 동작해야 한다"는 특수한 이유가 있을 때만 고려해볼 만한
선택이다.

## 같이 보기

- [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) — 이 Redis 세션 방식과 JWT의 실질적 비교(`STUDY-01`)
- [PHP](../WebDevelopment/PHP.md) — `redis_client.php`가 속한 언어, 소켓 통신(`fsockopen`) 사용
- [MariaDB](../Database/MariaDB.md) — 같은 프로젝트에서 영구 데이터를 담당하는 다른 저장소

## 참고자료

- [Redis 공식 문서](https://redis.io/docs/latest/)
- [RESP 프로토콜 명세](https://redis.io/docs/latest/develop/reference/protocol-spec/)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | `RottenNobleProject-Architecture.md` 2~3회차 코드 학습 중 Redis를 별도 주제로 분리 |
