# RottenNobleProject 아키텍처 이해하기

> 진행 상태: **완료** — 이 세션 일지(1~3회차)로 코드 구조를 다 훑었고, 여기서 나온 각 기술은
> 독립된 주제 문서로 분리해 정리했다. 전체 그림은
> [`RottenNoble-Project.md`](./RottenNoble-Project.md)(저장소 개요) 참고.

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

## 배운 것 (2026-09-08, 3회차 — 프런트-백엔드 통신 & 인증 흐름)

### 요청/응답 봉투

성공 `{status:'ok', data}` / 실패 `{status:'error', message}` — `frontend/src/api/posts.js`의
`request()`가 이 봉투를 까서 `status !== 'ok'`면 `Error(message)`를 던진다. 단, `auth.js`의
`login()`/`logout()`은 이 공통 `request()`를 안 쓰고 `fetch`를 직접 호출한다 — 로그인은 아직 토큰이
없어서 `authHeaders()`를 붙일 필요가 없는 자연스러운 예외지만, 봉투를 까는 로직(`body.status !== 'ok'`
검사)은 `auth.js`에도 똑같이 손으로 다시 써 있다 — 완전히 같은 코드가 두 파일에 한 번씩 더 반복됨.

### CORS 실동작 — 문서(MEMO-WEB-02)와 코드가 갈라진 지점

`response.php`의 `allow_cors($methods)`는 엔드포인트 종류와 무관하게 항상
`Access-Control-Allow-Origin: *`를 붙이고, `OPTIONS` 프리플라이트는 204로 즉시 종료한다. 그런데
`CODE_MEMO.md`의 `MEMO-WEB-02`는 명시적으로 이렇게 적어뒀다:

> "관리자 글쓰기/수정 같은 **인증 붙는 엔드포인트를 추가할 때 이 와일드카드를 그대로 복사하면 안 된다**
> — 그때는 쿠키/토큰이 오가므로 명시적 origin 허용목록으로 바꿔야 한다."

실제로는 `login.php`/`logout.php`/`create_post.php`/`update_post.php`/`delete_post.php` 전부
`allow_cors()`를 공유 함수 그대로 호출해서, 경고했던 그 와일드카드를 그대로 쓰고 있다 — 문서화된
결정과 실제 구현이 어긋난 지점.

**왜 지금 당장 위험하지 않은가**: 이 프로젝트는 쿠키가 아니라 `Authorization: Bearer {token}` 헤더로
인증한다. 브라우저는 쿠키와 달리 커스텀 헤더를 다른 origin 요청에 자동으로 붙여주지 않으므로,
`evil.com`의 스크립트가 `rotten-noble.com`에 요청을 보내도 토큰을 모르면(다른 origin의
`localStorage`는 읽을 수 없음) 인증을 통과시킬 방법이 없다 — 쿠키 기반이었다면 뚫렸을 클래식 CSRF가
여기선 토큰 저장 방식 자체 때문에 막혀 있다. 그래도 `MEMO-WEB-02`가 스스로 남긴 경고가 안 지켜진
채로 남아있다는 사실 자체는 기록해둘 만하다(고치자는 게 아니라, 문서-코드 드리프트 사례로).

### 인증 흐름 (로그인 → 요청 → 로그아웃)

1. `login.php` — `username`/`password`를 `config.local.php`의 `admin_user`/`admin_password_hash`와
   비교(`password_verify`, bcrypt류). 성공하면 `bin2hex(random_bytes(32))`로 32바이트 랜덤 토큰을
   만들고 Redis에 `SET admin_session:{token} 'admin' EX 86400`(24시간) 저장 후 `{token}` 반환.
2. 프런트 `auth.js`가 토큰을 `localStorage`(`rotten_admin_token`)에 저장.
3. 쓰기 요청(`createPost`/`updatePost`/`deletePost`)마다 `authHeaders()`가
   `Authorization: Bearer {token}`을 주입.
4. `auth.php`의 `require_admin()`이 헤더를 파싱해 Redis에서 `admin_session:{token}`을 `GET` — 값이
   정확히 `'admin'`이 아니면(만료·위조 포함) `401`로 즉시 종료.
5. `logout.php` — Redis에서 `DEL admin_session:{token}`. Redis 호출이 실패해도 조용히 넘어간다(주석:
   "클라이언트가 토큰을 버리면 사실상 끝나므로") — 로그아웃 실패를 사용자에게 보여줄 필요가 없다는
   판단.
6. 갱신(refresh) 로직은 없다 — 24시간 TTL이 지나면 Redis가 키를 자동 만료시키고, 다음 보호된 요청이
   그냥 401을 맞는다. 프런트는 이걸 미리 감지하지 않고, 실제 요청이 실패해야 알게 된다.

### UI 에러 처리 패턴

`Login.jsx`·`PostEditor.jsx` 둘 다 같은 모양이다 — 로컬 `error`/`submitting` state, `.catch(err =>
setError(err.message))`, 전역 에러 바운더리/토스트 없이 각 페이지가 자기 에러를 직접 그림. 로그인
성공 시엔 라우터 `navigate()` 대신 `window.location.href = '/'`로 **전체 새로고침**을 의도적으로
쓰는데, 주석에 이유가 있다 — `Nav`의 로그인 상태는 마운트 시점에만 읽으므로 전역 상태 라이브러리 없이
Nav를 확실히 최신화하려면 새로고침이 제일 간단하다는 판단(이 규모에 Redux/Context 도입은 과함).

### 결론 (3회차 한정)

인증 방식이 쿠키가 아니라 헤더 토큰이라는 선택 하나가, CORS 와일드카드가 남아있어도 클래식 CSRF는
막아주는 결과로 이어졌다 — 다만 이건 설계 당시 의도적으로 노린 방어라기보다 결과적으로 그렇게 된
쪽에 가까워 보인다(`MEMO-WEB-04`엔 Redis opaque 토큰을 고른 이유로 "즉시 무효화 가능"만 적혀있고
CORS와의 상호작용은 언급이 없음). `STUDY-01`(JWT vs 여기 Redis 세션)을 실제로 공부할 때, Redis TTL
24시간이 JWT의 `exp` 클레임과 같은 역할을 한다는 점 + "즉시 무효화"가 JWT엔 기본으로 없다는 트레이드
오프를 이 코드가 실물로 보여준다는 게 좋은 출발점이 될 것 같다.

## 다음에 볼 것

- `STUDY-01` 본편 — 여기서 실제로 본 Redis 세션 구현을 놓고 JWT였다면 무엇이 달라졌을지 비교 (같은
  `Study.md`의 STUDY-01 항목을 "학습 중"으로 바꾸고 시작)
- (선택, 이 학습 세션 범위 밖) `MEMO-WEB-02` 와일드카드 갭을 실제로 허용목록으로 바꿀지는 별도 결정
  사항으로 남겨둠 — 지금 당장 손대지 않음

## 참고자료

- `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md`
- `DevelopPrompt/CurrentProject/_RottenNobleProject/CODE_MEMO.md` (`MEMO-WEB-02`, `MEMO-WEB-04`)
- `DevelopPrompt/Web/08_PITFALLS.md` §2 (CRA Jest exports map 문제)
- `RottenNoble-Project`(`develop` 브랜치) — `backend/response.php`, `backend/db.php`, `backend/auth.php`,
  `backend/login.php`, `backend/logout.php`, `backend/create_post.php`, `backend/lib/redis_client.php`,
  `frontend/src/App.js`, `frontend/src/api/*.js`, `frontend/src/pages/Login/Login.jsx`,
  `frontend/src/pages/PostEditor/PostEditor.jsx`
