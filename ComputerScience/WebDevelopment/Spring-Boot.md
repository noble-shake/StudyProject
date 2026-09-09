# Spring Boot — 프레임워크가 "대신 해주는 일"이 정확히 뭔가

---

- **카테고리**: 웹 개발, 서버 사이드
- **상태**: 완료
- **기준 시점**: 2026-09-09
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

2026-09-08, 시니어 백엔드 개발자로부터 "PHP를 프레임워크 없이 손으로 짠 것과 CRA 둘 다 안 좋은
선택"이라는 피드백을 받은 뒤, 사용자가 백엔드를 Java Spring Boot로 전면 교체하기로 결정하면서
`server/` 모듈을 처음부터 새로 짜며 정리한 주제. [PHP](./PHP.md) 문서와 나란히 놓고 비교하는 게
목적이라, 그 문서는 지우지 않고 그대로 남겨뒀다 — 스택이 바뀌어도 이전 선택이 왜 있었는지는
여전히 배울 거리다.

## 정의

Spring Boot는 순수 자바로 웹 서버를 짤 때 반복되는 배선(라우팅 등록, DB 커넥션 관리, JSON
직렬화, 에러를 HTTP 응답으로 바꾸는 일 등)을 "관례(convention)"로 대신 처리해주는 프레임워크다.
핵심 메커니즘은 **의존성 주입(DI)**과 **자동 설정(auto-configuration)** 두 가지다 — 클래스에
`@Service`/`@Repository`/`@RestController` 같은 표시만 해두면, 프레임워크가 그 객체들을
필요한 곳에 알아서 연결해준다.

## 요약

`RottenNoble-Project`의 PHP 백엔드는 "파일 하나 = 엔드포인트 하나"였고, CORS·인증·DB 연결처럼
반복되는 코드를 `response.php`/`auth.php`/`db.php`로 손수 뽑아 재사용했다. Spring Boot는 그
"뽑아서 재사용하는" 일 자체를 프레임워크가 표준화된 방식(어노테이션 + DI)으로 대신해준다 —
장점은 실수할 여지가 줄어드는 것(CORS 프리플라이트 처리를 직접 안 짜도 됨), 단점은 그 관례를
먼저 배워야 코드를 읽을 수 있다는 것이다.

## 상세

### 의존성 주입 — "new를 누가 대신 해주는가"

```java
@RestController
@RequestMapping("/api/posts")
public class PostController {
    private final PostRepository postRepository;
    private final SessionService sessionService;

    public PostController(PostRepository postRepository, SessionService sessionService) {
        this.postRepository = postRepository;
        this.sessionService = sessionService;
    }
}
```

PHP 쪽 `create_post.php`는 `require 'db.php';`로 전역 `$conn` 변수를 만들어 쓴다. Spring에서는
`PostController`가 "나는 `PostRepository`와 `SessionService`가 필요하다"고 생성자에 선언만 하면,
스프링 컨테이너가 시작 시점에 그 객체들을 만들어서 넣어준다(생성자 주입) — 컨트롤러는 그
객체들이 "어떻게 만들어지는지"(DB 커넥션 풀 설정 등)를 전혀 몰라도 된다. 이 프로젝트는 필드에
`@Autowired`를 붙이는 방식 대신 항상 생성자 주입을 썼다 — 어떤 의존성이 필요한지 생성자
시그니처만 보면 바로 드러나고, 테스트할 때도 가짜 객체를 생성자로 그냥 넣어주면 되기 때문이다.

### 자동 설정 — "왜 Redis 연결 코드가 하나도 없는가"

`backend/lib/redis_client.php`는 RESP 프로토콜을 소켓으로 직접 구현한 60줄짜리 클래스였다.
`server/` 쪽에는 그런 코드가 아예 없다 — `spring-boot-starter-data-redis`를 의존성에 넣고
`application.yml`에 `spring.data.redis.host/port`만 써두면, `StringRedisTemplate`이라는 준비된
객체가 자동으로 만들어져서 아무 곳에나 주입해 쓸 수 있다. 이게 "자동 설정"이다 — 클래스패스에
뭐가 있는지, 설정 파일에 뭐가 적혀 있는지를 보고 필요한 빈(bean)들을 프레임워크가 알아서 등록해준다.

### 필요한 만큼만 가져오기 — `spring-boot-starter-security`를 안 쓴 이유

관리자 로그인 검증에 bcrypt 비교(`BCryptPasswordEncoder`) 하나만 필요했는데, 이걸 위해
`spring-boot-starter-security`(전체 자동 보안 필터 체인)를 넣으면 **기본값으로 모든 엔드포인트가
잠기고, 콘솔에 매번 랜덤 생성되는 임시 비밀번호가 찍히는** 스프링의 유명한 기본 동작이 같이
딸려온다. 이 프로젝트는 관리자가 1명이고 이미 Bearer 토큰 + Redis 세션이라는 직접 검증 로직이
있으므로, 전체 필터 체인 대신 `spring-security-crypto`(그 안의 `BCryptPasswordEncoder`)만
따로 의존성에 넣었다. "프레임워크가 다 해준다"는 걸 무조건 다 갖다 쓰는 게 아니라, **어떤 조각이
필요한지 판단하고 그 조각만 가져오는 것**도 프레임워크를 쓰는 능력의 일부라는 걸 보여주는
사례다.

### 크로스 언어 암호화 호환 — 가장 실수하기 쉬웠던 지점

PHP `backend/lib/crypto.php`에서 이미 AES-256-GCM으로 암호화해 저장한 방명록 데이터가 있어서,
Java 쪽도 같은 키로 그 값을 복호화할 수 있어야 했다([저장 데이터 암호화](../Security/Encryption-at-Rest.md)
참고). 문제는 두 언어의 GCM 구현이 **암호문과 인증 태그를 다루는 방식이 다르다**는 것이다.

```java
// Java: Cipher.doFinal()은 (암호문 + 태그)를 이어붙여서 반환/기대한다
byte[] ciphertextAndTag = cipher.doFinal(plaintext);
// PHP: openssl_encrypt(..., OPENSSL_RAW_DATA, $iv, $tag)는 태그를 별도 out-파라미터로 준다
$ciphertext = openssl_encrypt($plaintext, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag);
```

저장 포맷(`iv + tag + ciphertext`)을 두 언어에서 똑같이 맞추려면, Java 쪽에서 `doFinal()`이
반환한 덩어리의 마지막 16바이트(태그)를 잘라내 앞으로 옮기는 작업이 필요하다 — 반대로 복호화할
땐 저장된 (iv, tag, ciphertext)를 다시 (ciphertext + tag) 순서로 재조립해서 Java의 `Cipher`에
넘겨야 한다. 이 재배치를 빼먹으면 "같은 알고리즘, 같은 키인데 복호화가 안 되는" 상황이 되고,
에러 메시지도 "인증 실패"처럼 원인을 바로 알기 어려운 형태로 나온다 — 언어를 넘나드는 암호화
호환성을 다룰 때는 "같은 알고리즘 이름을 쓴다"만으로는 부족하고, 각 언어 라이브러리가 바이트를
정확히 어떤 순서로 주고받는지까지 맞춰야 한다는 걸 보여주는 사례다.

### (2026-09-09 추가) 실제로 컴파일·배포된 뒤 드러난 것들

이 문서를 처음 쓴 세션은 java/maven이 없는 환경이라 `server/` 모듈을 한 번도 컴파일해보지 못한
채 마무리됐다(그 PR #3는 결국 머지 없이 close됨). 실제 컴파일·배포는 다른 세션이 `backend-spring/`
라는 새 모듈명으로 다시 짜서 했고, 그 결과가 지금 프로덕션에서 돌고 있다(Spring Boot 4.1.1,
Java 21). 위 내용(DI, 자동 설정, `spring-boot-starter-security` 미사용, 크로스 언어 암호화)은
설계 시점에 세운 계획이었는데, 실제로 돌려본 뒤 드러난 것들은 다음과 같다.

- **Flyway로 마이그레이션을 관리한다.** `ddl-auto: validate`(JPA가 스키마를 직접 건드리지 않고
  검증만 함)만으로는 "기존 PHP 시절 스키마를 Spring 쪽 마이그레이션 이력에 어떻게 편입시키는가"가
  해결이 안 된다 — Flyway의 `baseline-on-migrate` 옵션으로 "이미 존재하는 스키마를 v1 베이스라인
  으로 인정하고 그 이후 변경분부터 마이그레이션 파일로 관리"하는 방식을 썼다(`V1__init.sql`).
  이건 "새 프로젝트에 마이그레이션 도구를 처음 들이는 것"과 "이미 데이터가 있는 운영 DB 위에
  마이그레이션 도구를 나중에 들이는 것"이 다른 문제라는 걸 보여주는 사례다.
- **경로 기반 라우팅이 안 되는 리버스 프록시를 만났다.** 원래 계획은 `rotten-noble.com/api/**`처럼
  기존 도메인 아래 경로로 새 백엔드를 붙이는 것이었지만, DSM 7.1.1의 리버스 프록시 기능이
  경로(path) 단위 라우팅을 지원하지 않아(호스트/포트 단위로만 갈래를 나눌 수 있음) 결국
  `api.rotten-noble.com`이라는 새 서브도메인을 따로 만들어 그쪽으로 백엔드 컨테이너를 붙였다 —
  `HashRouter`로 우회했던 `MEMO-WEB-05`와 같은 계열의 "인프라 GUI가 원하는 설정을 지원 안 해서
  구조를 바꿔 우회한" 패턴이 이번에도 반복됐다.
- **Lombok을 여전히 안 썼다.** 이번엔 실제로 컴파일이 가능한 환경이었는데도 게터/세터를 손으로
  계속 썼다 — 처음의 "검증할 방법이 없어서 보류"라는 이유는 더 이상 유효하지 않았지만, 이미
  Lombok 없이 시작한 코드베이스를 굳이 중간에 바꿀 이유가 없었던 것으로 보인다.
- **CORS·방명록 암호화는 이 배포에 안 들어갔다** — rate limiting은 이식됐지만 나머지 둘은
  아니다. 자세한 내용과 이유는 [CORS](../Network/CORS.md)와
  [저장 데이터 암호화](../Security/Encryption-at-Rest.md)의 "2026-09-09 갱신" 절 참고.

## 비교표

| | PHP (프레임워크 없음) | Spring Boot |
|---|---|---|
| 라우팅 | 파일 하나 = 엔드포인트 하나 | 어노테이션(`@GetMapping` 등)으로 메서드에 경로 매핑 |
| 의존성 연결 | `require`로 전역 변수/함수 공유 | 생성자 주입 — 프레임워크가 객체 그래프를 구성 |
| CORS 프리플라이트 | `allow_cors()`에서 `OPTIONS`를 직접 분기 처리 | `CorsRegistry` 설정만 하면 프레임워크가 처리 |
| DB 접근 | `mysqli` prepared statement를 직접 작성 | Spring Data JPA — 리포지토리 인터페이스만 선언 |
| 에러 → HTTP 응답 | 각 파일에서 `send_error()` 직접 호출 | 예외를 던지면 `@RestControllerAdvice`가 한 곳에서 변환 |
| 배우는 데 드는 비용 | 언어 문법만 알면 코드가 다 보임 | 프레임워크의 관례(어노테이션이 뭘 하는지)를 먼저 알아야 함 |

## 질문

- **Q. 프레임워크가 다 해주면 뭘 배우는 건가?**
  A. "무엇을 직접 짜야 하는가"의 범위가 바뀔 뿐, 배울 게 없어지는 건 아니다 — 대신 "이
  어노테이션을 붙이면 프레임워크가 정확히 무슨 일을 대신 해주는가"를 이해하는 게 새로운 학습
  대상이 된다. PHP 시절엔 CORS 프리플라이트를 직접 짜면서 그 동작을 배웠다면, Spring에서는
  `CorsRegistry`가 내부적으로 같은 일을 어떻게 처리하는지를 아는 게 그 자리를 대신한다.

- **Q. 왜 Lombok(보일러플레이트 자동 생성 라이브러리)을 안 썼나?**
  A. 이 프로젝트를 짠 환경엔 Java/Maven이 아예 없어서 컴파일 자체를 한 번도 못 해봤다. Lombok은
  애노테이션 프로세서를 pom.xml에 추가로 설정해야 하는데, 컴파일을 검증할 방법이 없는 상태에서
  그 설정이 미묘하게 틀릴 위험을 하나 더 얹고 싶지 않아서, 게터/세터를 그냥 손으로 다 썼다 —
  "프레임워크/라이브러리를 얼마나 들여올지"는 항상 "이걸 검증할 방법이 있는가"와 같이
  판단해야 한다는 것도 이번에 새삼 느낀 지점이다.

## 예시 코드

```java
// backend/response.php의 send_error()에 해당하는 자리 — 컨트롤러는 예외만 던지면 된다
throw new ApiException("게시글을 찾을 수 없습니다.", HttpStatus.NOT_FOUND);

// 한 곳에서 모든 컨트롤러의 예외를 가로채 {status:"error", message} 봉투로 바꾼다
@RestControllerAdvice
public class GlobalExceptionHandler {
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<ApiResponse<Void>> handleApiException(ApiException e) {
        return ResponseEntity.status(e.getStatus()).body(ApiResponse.error(e.getMessage()));
    }
}
```

## 플로우차트

`Spring-Boot.flow.md` 참고 — 요청 하나가 컨트롤러부터 예외 처리까지 어떤 순서로 지나가는지.

## 실무

실무에서 Spring Boot는 자바 서버 생태계의 사실상 표준이라 채용 공고 기준으로도 압도적으로 많이
쓰인다. 다만 "관례를 안다"는 전제가 깔려 있어서, 처음 합류하는 사람에게는 "이 어노테이션이 왜
여기 있는지" 자체가 진입 장벽이 되기도 한다 — 이번처럼 프레임워크 없는 버전을 먼저 짜본 다음에
같은 기능을 Spring으로 다시 짜보면, 그 관례가 "마법"이 아니라 "내가 직접 짰던 코드를 대신
해주는 것"이라는 걸 구체적으로 이해하게 된다는 게 이 학습 순서의 실질적인 장점이었다.

## 같이 보기

- [PHP](./PHP.md) — 이번에 대체된 이전 스택. 지워지지 않고 비교 대상으로 남아있다
- [저장 데이터 암호화](../Security/Encryption-at-Rest.md) — Java/PHP 간 암호화 포맷 호환의
  배경이 된 원래 설계
- [Rate Limiting](../Security/Rate-Limiting.md) — 같은 Redis INCR 패턴을 Spring에서 재구현
- [REST API 설계](./REST-API-Design.md) — 이번에 PHP의 "id를 body에 담은 POST" 방식에서
  경로 변수 기반 REST 관례로 바뀐 배경

## 참고자료

- [Spring Boot 공식 문서 — Auto-configuration](https://docs.spring.io/spring-boot/reference/using/auto-configuration.html)
- [Spring Security — Password Storage](https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | PHP 백엔드를 Spring Boot로 전면 교체하며 정리 |
| 2026-09-09 | 실제 컴파일·프로덕션 배포 후 드러난 것들(Flyway 베이스라인, 서브도메인 라우팅, CORS/암호화 미이식) 추가 | 최초 작성 세션은 컴파일 자체를 못 해봤고, 실제 배포는 다른 세션(다른 모듈명 `backend-spring/`)이 수행함 |
