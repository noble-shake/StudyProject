# RottenNobleProject 아키텍처 이해하기

> 진행 상태: **학습 중** — 환경(스택) 섹션만 끝남. 다음 세션에서 "다음은 뭘 더 파볼까요?"부터
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

## 다음에 볼 것 (미완료)

- 아키텍처 계층 — 폴더/파일이 실제로 어떻게 나뉘어 있는지
- 프런트-백엔드 통신 — API 봉투 형식, CORS
- 인증(로그인) 흐름 — Redis 세션 토큰이 실제로 어떻게 흐르는지 (`STUDY-01`과 자연스럽게 이어짐)

## 참고자료

- `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md`
- `DevelopPrompt/Web/08_PITFALLS.md` §2 (CRA Jest exports map 문제)
