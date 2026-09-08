# RottenNobleProject 아키텍처 이해하기

> 진행 상태: **학습 중** — 환경(스택) + 아키텍처 계층 섹션 끝남. 다음 세션은 "프런트-백엔드 통신"부터
> 이어가면 된다.

## 출처

`STUDY-nn` 백로그 항목이 아니라, `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md`
§1 목표 4번 — "사용자가 직접 코드를 읽고 학습할 예정"(2026-09-07 확인)에서 시작된 직접 코드 학습
세션. 어제(2026-09-07) 열심히 개발한 프로젝트라, 코드를 짜준 세션과 별개로 "이게 뭐고 왜 이렇게
했는지"를 하나씩 짚어가는 중.

## 계기 / 비교

RottenNobleProject를 처음부터 끝까지 다시 훑는다기보다, 사용자가 이미 만든 걸 스스로 이해하는 게
목적 — "환경 → 아키텍처 계층 → API 통신 → 인증 흐름" 순서로 천천히 갈 예정.

## 배운 것 (2026-09-08, 1회차 — 환경/스택)

| 구성요소 | 무엇인가 | 이 프로젝트에서 왜 이걸 썼나 |
|---|---|---|
| PHP 8.x, 프레임워크 없음 | 요청마다 실행되는 서버 사이드 스크립트. URL 경로가 파일 경로에 거의 그대로 대응(라우터 없음) | 규모(엔드포인트 10여 개)에 프레임워크가 과함 + "PHP를 직접 익히는 것" 자체가 목표라 프레임워크가 대신 해주는 라우팅/DB 접근을 직접 짬. 대가로 CORS/JSON 응답 처리가 여러 파일에 반복돼 `response.php`로 뽑아내야 했음 |
| React 19 (CRA) | 컴포넌트 단위로 화면을 만드는 프런트엔드 라이브러리 | React는 학습 목표에 부합해 그대로 감. 다만 이걸 감싸는 빌드 도구 CRA는 "이미 그렇게 시작되어 있었다"에 가까움 — 아래 STUDY-02로 이어짐 |
| MariaDB 10 | MySQL 오픈소스 포크, mysqli로 그대로 접속 | Synology NAS(Web Station)가 기본 지원하는 DB가 MariaDB라서 — NAS 배포가 이미 정해진 제약이라 거기 맞춘 선택 |
| XAMPP (로컬) | Apache+MariaDB+PHP+Perl을 한 번에 설치하는 로컬 개발 패키지 | 프로덕션이 Apache 기반 Synology Web Station이라, 로컬도 같은 Apache+PHP 조합으로 맞춰 "로컬에서 되면 배포해서도 될 확률"을 높임 |
| Synology NAS (프로덕션) | 집에 있는 개인 NAS를 웹 서버로 직접 운영 | **AWS 등 클라우드는 계속 비용이 드는데, 이미 개인용으로 갖고 있는 NAS가 있어서 그걸 활용** — 돈 내면서 클라우드 쓸 이유가 없다는 판단(2026-09-08 확인). 대신 포트 충돌·인증서 바인딩 등 클라우드였으면 안 겪었을 함정을 직접 겪음(`Web/08_PITFALLS.md`) — "직접 인프라를 만져보는 경험" 자체도 학습 목표라 감수 |

### 곁가지로 나온 이슈 — CRA vs Vite

React 자체는 문제없지만, 이걸 감싸는 빌드 도구 CRA(Webpack 기반, 2022년 이후 사실상 유지보수 중단)는
이미 이 프로젝트에서 실제 문제를 냈다 — `package.json`의 `exports` 필드를 CRA 내장 Jest가 못 읽어
`react-router-dom`을 import하는 코드가 **테스트에서만** 깨짐(`Web/08_PITFALLS.md` §2). Vite로
옮기면 이 문제 자체가 없어짐. React 자체를 Vue/Svelte로 바꾸는 건 학습 목표와 어긋나 검토 범위 밖,
Next.js는 PHP 백엔드를 따로 두는 이 프로젝트 구조와 부딪혀 제외. → 백로그로 분리 기록:
`DevelopPrompt/CurrentProject/_RottenNobleProject/Study.md`의 `STUDY-02`.

## 결론 (1회차 한정)

이 프로젝트의 스택 선택은 대체로 "표준적으로 제일 좋은 것"보다 **제약(NAS 고정, 학습 목적)에 맞춘
선택**이 많다 — MariaDB·XAMPP는 NAS 제약에서 역산됐고, PHP 무프레임워크는 학습 목적이 이유. 유일하게
"딱히 의도적으로 고른 게 아니라 그냥 따라온" 것이 CRA였고, 여기가 지금 유일하게 실제 대가(테스트
깨짐)를 치른 지점이기도 하다.

## 배운 것 (2026-09-08, 2회차 — 아키텍처 계층)

### 백엔드 (`backend/`) — "파일 하나 = 엔드포인트 하나", 공통 부분만 따로 뽑음

| 파일 | 계층 | 역할 |
|---|---|---|
| `get_posts.php`, `get_post.php`, `get_guestbook.php`, `create_guestbook_entry.php`, `create_post.php`, `update_post.php`, `delete_post.php`, `login.php`, `logout.php`, `index.php` | 엔드포인트(라우팅 없이 URL 경로 = 파일 경로) | 각 파일은 짧다 — `require 'response.php'; require 'db.php'; allow_cors(); <SQL 한두 줄>; send_json(...)` 패턴이 거의 전부. 프레임워크의 "컨트롤러"에 해당하는 걸 파일 단위로 쪼갠 것 |
| `response.php` | 공통 유틸(횡단 관심사) | `allow_cors()`(CORS 헤더 + OPTIONS 프리플라이트 처리) / `send_json()`·`send_error()`(`{status, data}` 또는 `{status, message}` 봉투로 통일 + `exit`) — 1회차에서 본 "반복되던 코드를 뽑아낸 지점"이 정확히 여기 |
| `db.php` | 공통 유틸(인프라) | `config.local.php`(gitignore)에서 접속정보를 읽어 mysqli 커넥션(`$conn`)을 전역으로 만들어줌. 각 엔드포인트는 `require`만 하면 `$conn` 사용 가능 — DI 컨테이너 없이 "그냥 전역 변수"로 해결한 게 특징 |
| `auth.php` | 미들웨어 역할(단, 프레임워크의 미들웨어 체인이 아니라 **함수 호출**) | `require_admin()` — `Authorization: Bearer {token}` 헤더를 파싱해 Redis의 `admin_session:{token}` 키를 조회, 값이 `'admin'`이 아니면 `send_error(401)`로 즉시 종료. 보호가 필요한 엔드포인트(`create_post.php` 등) 맨 위에서 이 함수 한 줄만 호출하는 방식 — Express의 미들웨어 개념을 프레임워크 없이 "가드 함수"로 흉내낸 형태 |
| `lib/redis_client.php` | 저수준 인프라 | Composer/phpredis 확장 없이 RESP 프로토콜(`*N\r\n$len\r\n...`)을 소켓으로 직접 구현한 최소 클라이언트(GET/SET EX/DEL만). **왜 직접 짰나** — 주석에 명시: `RottenNoble-HttpServer`(Node)·`RottenNoble-TCPServer`(C++/hiredis)와 **완전히 같은 Redis 인스턴스**를 같은 커맨드로 공유해야 해서, PHP만 라이브러리에 의존하면 프로토콜 세부동작이 미묘하게 갈릴 위험을 없앤 것. 세 언어가 한 Redis를 같은 방식으로 말하게 만든 설계 |
| `sql/schema.sql` | 데이터 계층 | 마이그레이션 도구 없이 수동 반영하는 스키마 원본 |

**계기/비교**: `HttpServer`/`TCPServer`는 이 블로그 프로젝트와 무관한 별도 리포지토리(`StylizedActionRPG`의
네트워킹 피어)인데, `admin_session:{token}` 세션만큼은 **같은 Redis 인스턴스와 같은 RESP 커맨드 패턴**을
세 프로젝트가 공유하고 있었다 — 프로젝트 경계와 인프라 공유 경계가 다르게 그어진 사례.

### 프런트엔드 (`frontend/src/`) — 백엔드와 대칭적인 "얇은 페이지 + 얇은 API 계층"

| 위치 | 역할 |
|---|---|
| `App.js` | `HashRouter`(BrowserRouter 아님 — NAS Apache가 SPA fallback rewrite를 안 갖췄을 가능성이 높아 보임, `#/posts/1`처럼 해시로 라우팅해 서버가 항상 `index.html`만 주면 되게 함) + `<Routes>`로 페이지 매핑. `Nav`가 로그인 상태(`isLoggedIn()`)에 따라 메뉴를 바꿈 |
| `pages/{Name}/{Name}.jsx` | 라우트 하나 = 폴더 하나(`PostList`, `PostDetail`, `PostEditor`, `Guestbook`, `Login`) — 백엔드의 "파일 하나 = 엔드포인트 하나"와 같은 결의 얇은 단위 분리 |
| `api/posts.js`, `api/auth.js`, `api/guestbook.js` | 백엔드 리소스 1개당 파일 1개. `posts.js`의 `request()` 헬퍼가 `fetch` 후 `{status, data}` 봉투를 까서 `status !== 'ok'`면 에러를 던짐 — 백엔드 `response.php`의 봉투 형식과 정확히 맞물리는 대칭 설계 |
| `api/auth.js` | 토큰을 `localStorage`(`rotten_admin_token`)에 저장, `authHeaders()`로 `Authorization: Bearer` 헤더를 만들어 `posts.js`의 쓰기 요청에 주입. 로그인 자체는 `fetch`를 직접 씀(공통 `request()` 안 거침 — 로그인은 아직 토큰이 없는 상태라 자연스러운 예외) |

### 결론 (2회차 한정)

양쪽 다 **"프레임워크가 주는 구조를 손으로 재현"**한 형태다 — 백엔드는 라우터 대신 파일 경로,
컨트롤러 대신 짧은 스크립트, 미들웨어 대신 가드 함수(`require_admin()`); 프런트는 관례적으로도 이미
"페이지 폴더 + API 계층 분리"가 표준적인 React 패턴이라 여기선 자연스럽게 나왔다. 유일하게 눈에 띄는
비표준 설계는 `lib/redis_client.php`를 직접 구현한 부분인데, 이건 "몰라서 직접 짠" 게 아니라
**세 언어(PHP/Node/C++)가 같은 Redis를 같은 방식으로 말해야 한다**는 명확한 이유가 있는 선택이었다.

## 다음에 볼 것 (미완료)

- 프런트-백엔드 통신 — API 봉투 형식과 CORS는 이번 회차에서 스쳐봤지만, 실패 케이스(네트워크 에러,
  401 흐름, OPTIONS 프리플라이트 실제 동작)는 아직 안 봄
- 인증(로그인) 흐름 — Redis 세션 토큰이 로그인부터 로그아웃까지 실제로 어떻게 흐르는지, `login.php`/
  `logout.php` 내부 (`STUDY-01`과 자연스럽게 이어짐)

## 참고자료

- `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md`
- `DevelopPrompt/Web/08_PITFALLS.md` §2 (CRA Jest exports map 문제)
- `RottenNoble-Project`(`develop` 브랜치) — `backend/response.php`, `backend/db.php`, `backend/auth.php`,
  `backend/lib/redis_client.php`, `frontend/src/App.js`, `frontend/src/api/*.js`
