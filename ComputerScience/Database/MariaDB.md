# MariaDB (와 mysqli)

---

**카테고리**: 웹 개발, 데이터베이스
**상태**: 완료
**기준 시점**: 2026-09-08, MariaDB 10.x 기준
**관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 코드 직접 학습 세션(1회차 환경/스택,
2회차 아키텍처 계층)에서 나온 주제.

## 정의

MariaDB는 MySQL에서 갈라져 나온(포크) 오픈소스 관계형 데이터베이스(RDBMS)다. MySQL을 인수한
오라클의 라이선스 정책 변화에 반발해 MySQL의 원 개발자들이 2009년에 시작한 프로젝트로, SQL 문법과
접속 방식이 MySQL과 거의 동일해서 "MySQL을 쓰던 코드를 그대로 MariaDB로 옮길 수 있다"는 게
핵심적인 특징이다. 실제로 이 프로젝트의 PHP 코드는 `mysqli`(MySQL Improved)라는, 이름부터 MySQL을
전제로 한 PHP 확장 모듈을 그대로 써서 MariaDB에 접속한다.

## 요약

RottenNobleProject가 MariaDB를 쓰는 이유는 "MariaDB가 기술적으로 더 낫다"는 판단이 아니라, 배포
대상인 Synology NAS(Web Station)가 기본으로 지원하는 DB가 MariaDB이기 때문이다 — 인프라 제약이
기술 선택을 역산한 사례다.

## 상세

### 왜 MySQL이 아니라 MariaDB인가

겉보기엔 "그냥 MySQL 쓰면 되지 않나" 싶을 수 있지만, 이 프로젝트의 실제 제약은 로컬 개발 환경이
아니라 **배포 환경**에서 나왔다. 프로덕션이 개인 소유 Synology NAS의 Web Station 위에서 돌아가는데,
Synology 패키지 센터가 기본으로 제공하는 관계형 DB 패키지가 MariaDB다. 클라우드였다면 AWS RDS에서
MySQL이든 MariaDB든 원하는 걸 고를 수 있었겠지만, "이미 갖고 있는 개인 NAS를 활용한다"는 이
프로젝트의 더 상위 결정(→ 인프라 문서 참고) 때문에, DB 선택은 사실상 NAS가 뭘 기본 지원하느냐로
정해졌다.

### `mysqli`를 쓴다는 것

PHP에서 MySQL 계열 DB에 접속하는 방법은 크게 세 가지 역사가 있다:

1. **`mysql_*` 함수들** — PHP 초창기 방식. 보안 문제(SQL 인젝션에 취약)와 설계 문제로 PHP 7에서
   완전히 제거됐다. 지금은 존재하지 않는다.
2. **`mysqli`** — `mysql_*`를 대체하기 위해 나온 확장. 절차적 스타일(`mysqli_query($conn, ...)`)과
   객체지향 스타일(`$conn->query(...)`)을 둘 다 지원한다. RottenNobleProject는 객체지향 스타일을
   쓴다.
3. **PDO(PHP Data Objects)** — DB 종류에 상관없이 같은 인터페이스로 접속할 수 있게 만든 더 최신
   추상화 계층. MySQL/MariaDB뿐 아니라 PostgreSQL, SQLite 등도 같은 코드 패턴으로 다룰 수 있다.

이 프로젝트는 현재 `mysqli`를 쓰고 있고, 실제로 `02_CODING_CONVENTION.md`에는 이걸 점진적으로
PDO로 옮겨가는 게 목표라고 기록돼 있다. `mysqli`가 당장 동작하지 않는 건 아니지만, DB를 바꿀
가능성이 조금이라도 있거나 여러 DB를 동시에 지원해야 한다면 PDO 쪽이 더 유연하다.

### SQL 인젝션과 prepared statement

`get_posts.php`처럼 사용자 입력이 전혀 안 들어가는 조회는 `$conn->query($sql)`로 SQL 문자열을
그대로 실행해도 안전하다. 하지만 사용자 입력(제목, 내용, 글 id 등)이 SQL에 섞여 들어가는
엔드포인트는 반드시 **prepared statement**를 쓴다:

```php
// backend/create_post.php
$stmt = $conn->prepare("INSERT INTO posts (title, content) VALUES (?, ?)");
$stmt->bind_param("ss", $title, $content);
$stmt->execute();
```

`?`는 값이 들어갈 자리를 미리 비워두는 자리표시자(placeholder)다. `bind_param("ss", ...)`의
`"ss"`는 뒤에 오는 두 값이 둘 다 문자열(string)이라는 타입 지정이다. 이렇게 하면 사용자가 제목
칸에 `'; DROP TABLE posts; --` 같은 걸 입력해도, DB는 그걸 "실행할 SQL 코드"가 아니라 "title
컬럼에 들어갈 순수한 문자열 값"으로만 취급한다 — SQL 인젝션이 원천적으로 막히는 이유다.

### 스키마 관리 — 마이그레이션 도구 없이 수동으로

```sql
-- backend/sql/schema.sql
CREATE TABLE IF NOT EXISTS posts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Laravel의 마이그레이션 시스템처럼 "스키마 변경 이력을 코드로 관리하고 자동으로 적용"하는 도구가
없다. 대신 `schema.sql` 파일 하나에 "지금 이 시점의 최종 스키마"를 적어두고, 로컬 XAMPP와 NAS
MariaDB 양쪽에 사람이 수동으로 반영한다. 테이블이 두 개뿐인 지금 규모에서는 이 정도로 충분하지만,
테이블이 늘어나거나 스키마 변경 이력을 추적해야 할 필요가 커지면 마이그레이션 도구 도입이 필요해질
지점이다 — 실제로 문서에도 "테이블이 더 늘면 도입 검토"라고 명시돼 있다.

## 비교표

| 항목 | MariaDB (이 프로젝트) | MySQL | PostgreSQL |
|---|---|---|---|
| 관계 | MySQL의 오픈소스 포크 | 원조, 현재 오라클 소유 | 별도 계보의 오픈소스 RDBMS |
| SQL 문법 호환성 | MySQL과 거의 동일 | - | 문법이 다름(더 표준 SQL에 가까움) |
| 라이선스 | 완전 오픈소스(GPL) 유지 | 오라클 소유, 상용 버전 존재 | 오픈소스(PostgreSQL 라이선스) |
| 이 프로젝트가 고른 이유 | Synology NAS 기본 지원 DB | (선택 안 함) | (선택 안 함) |

| PHP 접속 방식 | `mysqli` (현재 사용 중) | PDO |
|---|---|---|
| DB 종류 독립성 | MySQL 계열 전용 | 여러 DB를 같은 인터페이스로 |
| 이 프로젝트 상태 | 현재 사용, 점진적 전환 예정 | 목표 상태(미착수) |

## 질문

- **Q. `mysqli`에서 PDO로 바꾸면 실제로 뭐가 좋아지나?**
  A. 지금 당장은 MariaDB 하나만 쓰니 체감 이득이 크지 않다. 다만 PDO는 예외(exception) 기반 에러
  처리가 더 일관적이고, 코드 스타일이 DB 종류에 덜 종속적이어서 나중에 테스트용으로 SQLite를
  섞어 쓰는 등의 유연성이 생긴다.

- **Q. prepared statement 없이 `$conn->query()`로 사용자 입력을 넣으면 항상 위험한가?**
  A. 그렇다. 지금 `get_posts.php`·`get_guestbook.php`처럼 사용자 입력이 전혀 안 섞이는 SQL은
  `query()`로 실행해도 안전하지만, 조금이라도 사용자 입력이 SQL 문자열 조합에 들어간다면 반드시
  prepared statement로 바꿔야 한다. 이 프로젝트는 실제로 입력을 받는 모든 엔드포인트
  (`create_post.php`, `get_post.php`의 `?id=` 등)에서 이미 prepared statement를 쓰고 있다.

## 예시 코드

```php
// backend/get_post.php — id 파라미터가 있는 조회는 prepared statement로
$id = $_GET['id'] ?? null;
if ($id === null) {
    send_error('id가 필요합니다.', 400);
}

$stmt = $conn->prepare("SELECT id, title, content, created_at FROM posts WHERE id = ?");
$stmt->bind_param("i", $id); // "i" = integer
$stmt->execute();
$result = $stmt->get_result();
```

`bind_param`의 첫 인자가 각 값의 타입을 알려주는 문자열이라는 점을 기억해두면 좋다 — `i`는 정수,
`s`는 문자열, `d`는 실수, `b`는 바이너리(BLOB)다.

## 플로우차트

(생략 — 데이터 흐름이 "요청 → prepared statement 바인딩 → 실행 → 결과 반환"으로 선형적이라 표와
코드 예시만으로 충분하다.)

## 실무

실무에서는 MySQL과 MariaDB 둘 다 여전히 널리 쓰이고, 대부분의 팀은 "이미 어느 쪽 인프라를 쓰고
있느냐"로 선택이 정해지는 경우가 많다 — 이 프로젝트가 정확히 그런 사례다. PHP 진영에서는 이제
`mysqli`보다 PDO를 새 프로젝트의 기본으로 권장하는 분위기가 강하고, Laravel 같은 프레임워크는 아예
PDO 위에 자체 쿼리 빌더/ORM(Eloquent)을 얹어서 SQL을 직접 안 써도 되게 만든다. Prepared statement는
"SQL 인젝션 방지"의 실무 표준으로, 이 프로젝트가 이미 지키고 있는 부분이다.

## 같이 보기

- [PHP](../WebDevelopment/PHP.md) — `mysqli` 확장이 속한 언어, `db.php`가 커넥션을 만드는 방식
- [Redis](../Infrastructure/Redis.md) — 같은 프로젝트에서 관계형 데이터(글, 방명록)는 MariaDB, 세션 같은 휘발성
  데이터는 Redis로 나눠 쓰는 이유

## 참고자료

- [MariaDB 공식 문서](https://mariadb.org/documentation/)
- [PHP mysqli 확장 매뉴얼](https://www.php.net/manual/kr/book.mysqli.php)
- [PHP PDO 매뉴얼](https://www.php.net/manual/kr/book.pdo.php)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | `RottenNobleProject-Architecture.md` 1~2회차 코드 학습 중 DB 계층을 별도 주제로 분리 |
