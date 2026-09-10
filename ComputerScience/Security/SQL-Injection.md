# SQL Injection — 쿼리에 데이터가 아니라 명령이 섞여 들어갈 때

---

- **카테고리**: 데이터베이스, 네트워크/보안
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: -

---

## 출처

2026-09-08, 실제 배포된 `rotten-noble.com`을 대상으로 스캔/프로빙 활동이 있었고 그 안에 SQL
인젝션 시도가 포함돼 있었다(`Rate-Limiting.md`와 같은 사건). 같은 날 사용자가 시니어 백엔드
개발자에게 코드 리뷰를 받으면서 이 주제가 다시 짚였다 — RottenNobleProject의 직접 코드 학습
세션에서 나온 주제로, 별도 `STUDY-nn` 백로그 항목은 아니다.

## 정의

SQL 인젝션은 사용자가 입력한 값이 SQL 쿼리 문자열 안에 그대로 섞여 들어가서, 원래 의도한
"데이터"가 아니라 "명령의 일부"로 해석되게 만드는 공격이다. 서버가 사용자 입력을 데이터와 코드를
구분하지 못한 채 문자열을 이어붙여 쿼리를 만들면, 공격자는 그 문자열 조합 규칙을 역이용해 쿼리의
구조 자체를 바꿔버릴 수 있다.

## 요약

RottenNobleProject는 실제로 SQL 인젝션 시도를 받았지만 뚫리지 않았다 — PHP 시절부터 모든
DB 접근이 이어붙이기가 아니라 **준비된 문(prepared statement)**으로 되어 있었기 때문이다. 이번
Spring Boot 이관에서도 Spring Data JPA를 쓰면서 같은 안전성이 기본으로 유지된다. 이 문서는
"왜 준비된 문이면 막히는가"와 "그 방어가 새 스택에서도 정말 그대로 유지되는가"를 짚는다.

## 상세

### 왜 문자열 이어붙이기가 위험한가

가장 흔한 실수 패턴은 이런 모양이다(RottenNobleProject에는 없는, 설명을 위한 가상 코드):

```php
// 위험한 예시 — 이 프로젝트에는 이렇게 짠 곳이 없다
$id = $_GET['id'];
$sql = "SELECT * FROM posts WHERE id = " . $id;
$result = $conn->query($sql);
```

`id`가 `3`처럼 정상적인 숫자면 문제없이 동작한다. 하지만 공격자가 `id`에
`3 OR 1=1`을 넣으면 최종 쿼리는 `SELECT * FROM posts WHERE id = 3 OR 1=1`이 되고,
`1=1`은 항상 참이라 테이블의 모든 행이 조회된다. 더 나아가 `3; DROP TABLE posts;--` 같은
값을 넣으면(드라이버/DB 설정에 따라 다중 문장 실행이 허용되는 경우) 테이블 자체를 지워버리는
명령까지 실행될 수 있다. 핵심은 서버가 "이건 사용자가 준 값이다"와 "이건 내가 짠 쿼리 구조다"를
문자열 이어붙이기 시점에는 전혀 구분하지 못한다는 것이다.

### 준비된 문(prepared statement)이 막는 방식

RottenNobleProject의 PHP 코드는 처음부터 이렇게 짜여 있었다:

```php
// backend/get_post.php — 실제 이 프로젝트 코드
$stmt = $conn->prepare("SELECT id, title, content, created_at FROM posts WHERE id = ?");
$stmt->bind_param("i", $id);
$stmt->execute();
```

`?`는 값이 들어갈 자리를 미리 표시해두는 자리표시자(placeholder)다. `prepare()` 단계에서
DB 서버는 쿼리의 **구조**(어떤 테이블을, 어떤 조건으로)를 먼저 확정하고 실행 계획까지 세운다.
그 다음 `bind_param`으로 넘어가는 값은 그 확정된 구조 안의 "데이터"로만 취급되지, 쿼리 문자열에
다시 끼워 넣어져 재해석되는 게 아니다. `$id`에 `3 OR 1=1`이라는 문자열이 통째로 들어와도, DB는
그걸 "id 컬럼과 비교할 문자열 값"으로만 보지 새로운 쿼리 조건으로 보지 않는다 — 애초에 구조와
데이터가 서로 다른 채널로 전달되기 때문에 뒤섞일 방법이 없다.

### Spring Boot(JPA)에서는 왜 기본으로 안전한가

Spring Data JPA의 리포지토리 메서드는 내부적으로 Hibernate가 생성하는 파라미터 바인딩 쿼리를
쓴다:

```java
// backend-spring — PostRepository.java
List<Post> findAllByOrderByCreatedAtDesc();

// PostService.java에서
repository.findById(id) // id는 파라미터로 바인딩되지, 문자열로 이어붙여지지 않는다
```

메서드 이름을 분석해서 쿼리를 만드는 이 방식(Query Method)은 애초에 사용자가 SQL 문자열
자체에 손댈 여지를 주지 않는다 — 이어붙일 문자열 자체가 코드 어디에도 없다. 위험은 오히려
"쿼리 메서드로 표현이 안 돼서 직접 JPQL/네이티브 쿼리를 문자열로 짤 때" 생긴다:

```java
// 위험한 예시 — 이 프로젝트에는 없지만, JPA를 쓴다고 무조건 안전한 건 아니라는 걸 보여주는 코드
String jpql = "SELECT p FROM Post p WHERE p.title = '" + userInput + "'"; // 여전히 이어붙이기
entityManager.createQuery(jpql).getResultList();
```

즉 "ORM/프레임워크를 쓰면 자동으로 안전하다"가 아니라 "쿼리 메서드나 `@Param` 바인딩처럼
자리표시자를 쓰는 경로로만 다니면 안전하다"가 더 정확한 문장이다. RottenNobleProject는 현재
전부 쿼리 메서드로 처리되어 이 위험 경로 자체가 코드에 없다.

## 비교표

| 방식 | 안전한가 | 이 프로젝트에서 |
|---|---|---|
| 문자열 이어붙이기 (`"... WHERE id = " . $id`) | 안전하지 않음 | 사용된 적 없음 |
| 준비된 문 + 자리표시자 (`bind_param`) | 안전함 | PHP 시절 전 구간 사용 |
| JPA 쿼리 메서드 (`findById` 등) | 안전함 | Spring Boot 전환 후 전 구간 사용 |
| JPQL/네이티브 쿼리를 문자열로 직접 조립 | 안전하지 않음(자리표시자 안 쓰면) | 사용된 적 없음 |

## 질문

- **Q. 이번에 실제로 뚫렸나?**
  A. 아니다. 스캔/프로빙 로그에서 인젝션 시도 패턴이 확인됐지만, 전체 DB 접근 엔드포인트를
  재감사한 결과 문자열 이어붙이기 쿼리가 하나도 없어 시도 자체가 그대로 실패했다. 그날 실제로
  드러난 진짜 갭은 인젝션이 아니라 로그인의 rate limit 부재였다(`Rate-Limiting.md`).

- **Q. Prepared statement만 쓰면 DB 관련 보안은 다 해결되나?**
  A. 인젝션 한정으로는 그렇다. 다만 이 프로젝트가 별도로 겪은 `Web/08_PITFALLS.md` §7 문제
  (Docker 컨테이너가 브릿지 네트워크라 `root@localhost` 계정으로 거부당한 것)를 해결하며 도입한
  "이 DB 하나에만 권한을 가진 전용 계정"도 같은 방향의 방어다 — 인젝션이 뚫리더라도 그 계정이
  볼 수 있는 범위 자체를 최소화하는 최소 권한 원칙(principle of least privilege)이라, 인젝션
  방어와는 층이 다르지만 같이 짚어둘 가치가 있다.

- **Q. NoSQL(Redis)도 인젝션에서 자유로운가?**
  A. Redis는 명령어와 인자가 프로토콜 수준에서 분리되어 있어(RESP 프로토콜) 이 프로젝트처럼
  `SET key value EX seconds` 식으로 인자를 배열로 넘기는 한 SQL 인젝션과 같은 문제는 생기지
  않는다. 다만 "NoSQL 인젝션"이라는 별도 범주(예: 사용자 입력을 명령어 자체로 실행하는 `EVAL`
  스크립트에 그대로 넣는 경우)는 존재한다 — 이 프로젝트는 그런 경로를 쓰지 않는다.

## 예시 코드

```php
// 이 프로젝트가 실제로 쓰는 방식 (backend/create_post.php)
$stmt = $conn->prepare("INSERT INTO posts (title, content) VALUES (?, ?)");
$stmt->bind_param("ss", $title, $content);
$stmt->execute();
```

```java
// Spring Boot 쪽 동일 지점 (PostService.java)
Post post = new Post();
post.setTitle(title);
post.setContent(content);
repository.save(post); // Hibernate가 파라미터 바인딩된 INSERT를 생성
```

## 실무

실무에서는 준비된 문/ORM을 기본으로 쓰는 것 외에, 방어를 여러 겹으로 둔다 — 입력값 검증(길이·
형식 제한, 이 프로젝트도 제목 255자·내용 필수 같은 검증을 이미 하고 있다), WAF(Web Application
Firewall)로 알려진 인젝션 패턴을 요청 단계에서 미리 차단, DB 계정의 최소 권한 부여, 그리고
정기적인 의존성/쿼리 감사가 함께 간다. "프레임워크가 알아서 막아준다"고 방심하지 않고, 직접
문자열 쿼리를 짜야 하는 예외 상황(복잡한 동적 정렬, 리포팅 쿼리 등)에서 특히 주의하는 게
실무에서 자주 강조되는 지점이다.

## 같이 보기

- [Rate Limiting](./Rate-Limiting.md) — 같은 스캔/프로빙 사건에서 실제로 뚫렸던 갭
- [Frontend Code Exposure](./Frontend-Code-Exposure.md) — 같은 날 시니어 리뷰에서 나온 또 다른
  보안 주제

## 참고자료

- [OWASP — SQL Injection](https://owasp.org/www-community/attacks/SQL_Injection)
- [OWASP Cheat Sheet — Query Parameterization](https://cheatsheetseries.owasp.org/cheatsheets/Query_Parameterization_Cheat_Sheet.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 실제 스캔/프로빙 사건 + 시니어 백엔드 리뷰에서 나온 주제 정리 |
