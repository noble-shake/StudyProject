# 고정 API 키 인증 — 로그인이 아니라 "정해진 상대"를 확인하는 방법

---

- **카테고리**: 보안, 웹 개발
- **상태**: 완료
- **기준 시점**: 2026-09-10
- **관련 레포지토리**: `RottenNoble-WatchSyncServer`
- **엔진**: `Web`

---

## 출처

- `RottenNoble-WatchSync` `STUDY-01` — `DevelopPrompt/CurrentProject/_RottenNoble-WatchSync/Study.md`

## 정의

**API 키 인증**은 클라이언트가 매 요청마다 고정된 비밀 문자열(키) 하나를 헤더에 실어 보내고,
서버는 그 문자열이 미리 정해둔 값과 같은지만 확인하는 인증 방식이다. [JWT vs Redis
세션](./JWT-vs-Redis-Session.md)이 다루는 두 방식과 근본적으로 다른 전제를 깐다 — 세션과 JWT는
둘 다 "로그인이라는 이벤트가 있고, 그 결과로 토큰을 **발급**한다"는 모델이지만, API 키는 애초에
발급 과정이 없다. 키는 배포 시점에 미리 정해서 양쪽(서버·클라이언트)에 똑같이 심어두는 값이다.

## 요약

`RottenNoble-WatchSyncServer`는 사람이 로그인하는 시스템이 아니다 — Bridge(Mac 상주 프로세스)와
Wear(워치 앱)라는, 미리 정해진 두 클라이언트만 이 API를 부른다. "누가 로그인했는지"를 추적할
필요가 없고, "이 요청이 우리 Bridge/Wear가 보낸 게 맞는가"만 확인하면 된다 — 그래서 세션이나
JWT 같은 사용자 인증 모델 대신, 훨씬 단순한 고정 API 키를 골랐다(`MEMO-WATCHSYNC-01`). 대신
구현에서 놓치기 쉬운 지점 하나(문자열 비교 방식)는 제대로 처리했다.

## 상세

### 왜 세션도 JWT도 아닌가 — "로그인"이라는 개념 자체가 없다

`RottenNoble-Project`의 Redis 세션과 JWT는 둘 다 "불특정 사용자가 로그인한다"는 전제 위에
설계됐다 — 그래서 토큰 발급·만료·무효화라는 생명주기가 필요하다. WatchSync는 클라이언트가
**정확히 둘**(Bridge, Wear)이고, 둘 다 사람이 아니라 이 프로젝트 소유자 본인이 배포한 프로세스다.
"누가 요청했는지 식별"이 아니라 "우리가 만든 클라이언트가 맞는지 확인"이 목적이라, 로그인
이벤트도 토큰 발급 엔드포인트도 필요 없다 — 키를 서버·Bridge·Wear 세 군데 설정 파일에 똑같이
심어두는 것으로 끝난다.

```java
// RottenNoble-WatchSyncServer — ApiKeyInterceptor.java
@Component
public class ApiKeyInterceptor implements HandlerInterceptor {
    private final String configuredApiKey;

    public ApiKeyInterceptor(@Value("${watchsync.api-key}") String configuredApiKey) {
        this.configuredApiKey = configuredApiKey;
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        // ... @RequireApiKey가 붙은 메서드에서만 아래를 검사(RottenNoble-Project의
        // @RequireAdmin과 같은 패턴 — Spring-Boot.md 참고)
        String providedKey = request.getHeader("X-API-Key");
        if (providedKey == null || !constantTimeEquals(providedKey, configuredApiKey)) {
            throw new UnauthorizedException("API 키가 없거나 올바르지 않습니다.");
        }
        return true;
    }
}
```

### 놓치기 쉬운 지점 — 문자열 비교는 "같다/다르다"만이 아니다

`providedKey.equals(configuredApiKey)`처럼 평범하게 비교하면 **동작은 맞다.** 문제는 그게 얼마나
"빨리" 틀렸다고 답하는지가, 어디서 틀렸는지에 따라 달라진다는 점이다. 대부분의 문자열 비교
구현(자바의 `String.equals` 포함)은 앞에서부터 한 글자씩 비교하다가 **처음 다른 글자를 만나는
순간 바로 멈춘다.** 즉 "aXXXX...(진짜 키와 첫 글자만 다름)"는 "ZZZZZ...(전부 다름)"보다 아주
조금 더 오래 걸린다 — 그 차이가 나노초 단위라도, 네트워크 지연의 노이즈를 통계적으로 걸러낼 만큼
충분히 많이 반복해서 요청을 보내면(수천~수만 번), 공격자는 "어느 자리까지 맞았는지"를 응답
시간만으로 한 글자씩 추측해나갈 수 있다 — 이게 **타이밍 공격(timing attack)**이다.

```java
// 이렇게 하지 않는다 — 응답 시간이 "몇 번째 글자에서 틀렸는지"를 누설한다
if (!providedKey.equals(configuredApiKey)) { throw new UnauthorizedException(...); }

// 대신 — 항상 두 문자열의 전체 길이만큼 비교해서, 어디서 틀렸든 걸리는 시간이 같다
MessageDigest.isEqual(
    providedKey.getBytes(StandardCharsets.UTF_8),
    configuredApiKey.getBytes(StandardCharsets.UTF_8)
);
```

`MessageDigest.isEqual`(자바 표준 라이브러리)은 이런 상수 시간(constant-time) 비교를 보장하도록
문서화돼 있다 — 이름이 "메시지 다이제스트"(해시) 클래스에 있는 건 원래 해시값끼리 비교할 때 쓰라고
만들어진 메서드라 그렇다. API 키 비교에도 정확히 같은 문제(둘 다 "비밀값과 같은지"를 확인하는
비교)가 있어서 그대로 재사용할 수 있다.

### 세 플랫폼, 같은 원칙 — 비밀값은 코드에 안 들어간다

WatchSync는 서버(Java)·Bridge(Python)·Wear(Kotlin/Android) 세 가지 완전히 다른 플랫폼이 **같은
키 값**을 알아야 하는데, 셋 다 `DevelopPrompt/Web/01_PROJECT_SETUP.md` §2의 "비밀값은 git에 커밋되는
파일에 안 들어간다" 원칙을 각 플랫폼의 관례로 구현했다:

| 플랫폼 | 커밋되는 파일 | 커밋 안 되는 실제 값 |
|---|---|---|
| Server (Spring Boot) | `application-local.example.yml`(빈 템플릿) | `application-local.yml`(`.gitignore`) |
| Bridge (Python) | `.env.example`(빈 템플릿) | `.env`(`.gitignore`) |
| Wear (Android) | `local.properties.example`(빈 템플릿) | `local.properties`(Android 프로젝트 관례상 원래도 `.gitignore`) → 빌드 시 `BuildConfig.API_KEY`로 노출 |

같은 원칙이 세 생태계에서 서로 다른 이름의 파일로 구현된다는 것 자체가, "비밀값 분리"가 특정
언어의 기능이 아니라 **환경변수/빌드타임 주입이라는 일반적인 패턴**이라는 걸 보여준다.

## 비교표

| 항목 | 고정 API 키 (WatchSync) | Redis 세션 | JWT |
|---|---|---|---|
| 전제 | 정해진 소수의 클라이언트 | 불특정 다수의 사용자 로그인 | 불특정 다수의 사용자 로그인 |
| 발급 과정 | 없음(배포 시 미리 심어둠) | 로그인 성공 시 발급 | 로그인 성공 시 발급 |
| 키/토큰이 여러 개인가 | 보통 하나(클라이언트 전체가 공유) | 사용자·세션마다 다름 | 사용자·세션마다 다름 |
| 검증 방법 | 상수 시간 문자열 비교 | 저장소(Redis) 조회 | 서명 검증 |
| 개별 무효화 | 안 됨(키를 바꾸면 전체가 다 끊김) | 됨(토큰 하나만 `DEL`) | 기본으로는 안 됨 |
| 만료 | 없음(수동 교체 전까지 영구) | TTL로 자동 | `exp` 클레임으로 자동 |
| 구현 복잡도 | 가장 단순 | 중간(저장소 필요) | 중간~높음(서명 키 관리) |

## 질문

- **Q. 키가 하나뿐이면, Bridge가 유출됐을 때 Wear까지 같이 막히지 않나?**
  A. 맞다 — 이게 이 방식의 가장 명확한 한계다. 클라이언트별로 다른 키를 발급하면 해결되지만,
  그러려면 "키를 누구에게 발급했는지" 관리하는 저장소가 필요해지고, 그 순간 API 키 방식의
  장점("발급 과정이 없다")이 사라진다. WatchSync는 클라이언트가 둘뿐이고 전부 본인이 통제하는
  기기라, 이 트레이드오프를 감수할 만하다고 판단했다(`MEMO-WATCHSYNC-01`). 클라이언트 수가
  늘어나거나 제3자에게 API를 열어준다면 이 판단부터 재검토해야 한다.

- **Q. 그럼 왜 애초에 세션이나 JWT를 안 썼나 — 나중에 확장하기엔 API 키가 불리하지 않나?**
  A. 맞는 지적이다. 다만 "확장 가능성에 대비해 지금 더 복잡한 걸 먼저 깐다"는 선택 자체가
  [Redis](../Infrastructure/Redis.md) 문서에서 이미 한 번 다룬 것과 같은 종류의 과설계
  위험이다 — 지금 필요한 것(둘뿐인 정해진 클라이언트 확인)에 맞는 가장 단순한 도구를 쓰고,
  실제로 클라이언트가 늘어나는 신호가 오면 그때 세션/JWT로 옮기는 게 `03_ARCHITECTURE.md` §1의
  "신호가 오기 전에 미리 깔지 않는다" 원칙과 맞다.

- **Q. `MessageDigest.isEqual`을 안 쓰고 그냥 `.equals()`를 썼으면 실제로 뚫렸을까?**
  A. 이론적으로는 가능하지만, 로컬 네트워크(같은 집 안 Bridge/Wear ↔ 서버)처럼 지연 시간의
  노이즈가 낮고 공격자가 수만 번 요청을 반복하기 어려운 환경에서는 실무적 위험은 낮다. 그래도
  상수 시간 비교는 코드 한 줄 차이로 얻는 방어라 비용이 거의 없다 — "위험이 낮으니 생략해도
  된다"보다 "비용이 없으니 그냥 한다"가 여기서는 더 합리적인 판단이다.

## 예시 코드

```java
// 상수 시간 비교 — 자바 표준 라이브러리만으로 구현
private boolean constantTimeEquals(String a, String b) {
    return MessageDigest.isEqual(
        a.getBytes(StandardCharsets.UTF_8),
        b.getBytes(StandardCharsets.UTF_8)
    );
}
```

```python
# Python이었다면 표준 라이브러리의 동일한 목적 함수 — WatchSync의 Bridge는 API 키를
# "검증"하는 쪽이 아니라 "보내는" 쪽이라 실제로 쓰진 않지만, 반대 역할을 Python으로 구현한다면
# 이걸 쓴다.
import hmac
hmac.compare_digest(provided_key, configured_key)
```

## 플로우차트

이 검사는 "헤더 확인 → 상수 시간 비교 → 통과/거부"라는 3단계 직선 흐름이라, 분기나 상태 전이가
없다 — [JWT vs Redis 세션](./JWT-vs-Redis-Session.md)의 로그인~무효화 생명주기와 달리 그림으로
남길 만큼 복잡하지 않다고 판단해 플로우차트는 만들지 않았다.

## 실무

API 키는 실무에서 특히 **서버-투-서버(M2M) 또는 서드파티 API 접근**에 흔히 쓰인다(Stripe,
AWS Access Key, 각종 SaaS의 "API 키 발급" 기능 등). 다만 실무 시스템 대부분은 WatchSync처럼
"키 하나를 클라이언트 전체가 공유"하지 않고, **클라이언트/고객사마다 별도 키를 발급**하고 그 키를
DB에 저장해 조회·회전(rotation)·폐기할 수 있게 관리한다 — 그 관리 계층이 생기는 순간 사실상
"토큰을 저장소에 두고 조회한다"는 세션 방식에 가까워진다. WatchSync가 키 하나만 쓰는 건 실무의
일반적인 API 키 운영과는 다른, 클라이언트 수가 고정된 개인 프로젝트 규모에 맞춘 단순화다.

## 같이 보기

- [JWT vs Redis 세션](./JWT-vs-Redis-Session.md) — 사용자 로그인을 전제하는 두 방식과의 비교
- [Spring Boot](../WebDevelopment/Spring-Boot.md) — `@RequireApiKey`/인터셉터 패턴이 `@RequireAdmin`과
  같은 프레임워크 관례를 재사용한 배경
- [Redis](../Infrastructure/Redis.md) — "이 규모엔 과설계"라는 같은 판단을 다른 인프라 선택에 적용한 사례

## 참고자료

- [OWASP — REST Security Cheat Sheet (Authentication)](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)
- [Java `MessageDigest.isEqual` 문서](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/MessageDigest.html#isEqual(byte%5B%5D,byte%5B%5D))
- `DevelopPrompt/CurrentProject/_RottenNoble-WatchSync/CODE_MEMO.md`의 `MEMO-WATCHSYNC-01`/`MEMO-WATCHSYNC-02`

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-10 | 최초 작성, `STUDY-01` 학습 완료로 표시 | WatchSyncServer의 `ApiKeyInterceptor` 구현을 계기로 정리 |
