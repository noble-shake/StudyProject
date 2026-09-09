# StudyProject

> **세션을 시작하면 먼저 `DevelopPrompt`를 본다.** 이 저장소 자체엔 규칙이 없다 — 이 저장소가 어떻게
> 쓰이는지의 정책은 `DevelopPrompt/POLICY/STUDY.md`("StudyProject 연동" 절)에 있고, "왜 이 주제가
> 궁금해졌는지"의 배경은 `DevelopPrompt/CurrentProject/_{프로젝트명}/Study.md`의 각 `STUDY-nn` 항목에
> 있다. 여기 문서만 보고 시작하지 않는다.

Study with DevelopPrompt — 여러 프로젝트에서 궁금해졌던 것(각 프로젝트의 `Study.md` 백로그)을 실제로 파고들어 공부한 내용을 쌓는 저장소입니다.

각 프로젝트의 `Study.md` 항목과 여기 내용을 서로 링크해서, "왜 궁금해졌는지"는 원래 프로젝트에, "실제로 무엇을 배웠는지"는 여기에 남깁니다.

## 브라우저로 보기

저장소 루트의 [`build_bundle.cmd`](build_bundle.cmd)를 더블클릭하면 이 저장소의 모든 `.md`
문서를 한 번에 내장한 `DOCS_BUNDLE.html`이 생성됩니다 — 그 파일 하나만 더블클릭해서 열면 사이드바
탐색(카테고리별 그룹) + 검색이 되는 문서 뷰어로 전부 읽을 수 있습니다(`DevelopPrompt/VIEWER`와
같은 엔진을 그대로 재사용, 자세한 건 [`VIEWER/README.md`](VIEWER/README.md)). `DOCS_BUNDLE.html`은
파생물이라 `.md`가 원본이고, 문서를 고치면 다시 만들어야 최신 내용이 반영됩니다.

## 구조

- **카테고리별 폴더 트리로 정리한다** — `ComputerScience/{분야}/{주제}.md` (예:
  `ComputerScience/Network/CORS.md`). 분야 폴더는 필요에 따라 늘어난다(현재:
  `WebDevelopment`, `Database`, `Infrastructure`, `Security`, `Network`, `Architecture`, `Graphics`).
  주제 하나가 여러 카테고리에 걸치면(문서 상단 메타의 "카테고리" 필드는 1~3개 가능) 가장 주된
  분야의 폴더에 두고, 메타 필드로 나머지를 표시한다 — 폴더는 하나, 태그는 여러 개.
- 새 주제를 시작할 때 [`_TEMPLATE.md`](_TEMPLATE.md)를 복사해서, 해당 카테고리 폴더 안에 쓴다.
  맞는 카테고리 폴더가 아직 없으면 새로 만든다.
- 문서 상단엔 항상 어느 프로젝트의 어느 `STUDY-nn`에서 왔는지 백링크를 남긴다.
- 다 배우면 원본 `Study.md` 쪽 항목 상태를 "완료"로 바꾸고 결론 한 줄 + 이 저장소 문서 경로를
  덧붙인다(내용 자체는 `Study.md`로 복사하지 않는다 — 원본은 항상 여기 하나뿐).
- **문체가 `DevelopPrompt`와 다르다.** `DevelopPrompt`의 정책·`CODE_MEMO.md`는 AI 에이전트가 빠르게
  훑도록 압축한 컨텍스트 문서지만, 여기는 **사람이 읽고 배우는 교재**다. 개념을 실제로 설명하는
  문장으로 풀어 쓰고, 표는 비교·정리용으로만 쓴다 — 자세한 형식은 `_TEMPLATE.md` 참고.
- **레포지토리 하나를 전체적으로 다룰 땐 개요 문서를 하나 더 둔다.** 개별 기술 문서들과 별개로,
  그 저장소가 속한 카테고리 폴더(주로 `Architecture/`) 안에 `{저장소명}.md` 형태로 아키텍처
  요약·기술 스택 표·특이할 점을 모은 색인 문서를 만든다 (예:
  [`ComputerScience/Architecture/RottenNoble-Project.md`](ComputerScience/Architecture/RottenNoble-Project.md)).
  개별 문서가 "나무"라면 이 문서는 "숲"이다.

## 카테고리 지도

```
ComputerScience/
├── Architecture/        저장소 개요, 코드 직접 학습 세션 기록
├── Graphics/            렌더링/포스트 프로세싱 일반 이론(톤 매핑 커브, TAA 등), 특정 엔진에 종속되지 않는 개념
├── URP_PostProcessing/  Unity URP `Post Process Data`에 실제로 참조된 개별 셰이더(LUT PS 등) 전용
├── Database/            MariaDB, mysqli, SQL
├── Infrastructure/      Redis, 배포, 자체 호스팅
├── Network/             CORS, HTTPS, HTTP 프로토콜 일반
├── Security/            인증·인가, 해싱, 토큰 저장
└── WebDevelopment/      PHP, React, 라우팅, API 설계
```

## 항목 인덱스

### RottenNoble-Project 전체

| 주제 | 출처(프로젝트 · STUDY-nn) | 관련 레포지토리 | 상태 |
|---|---|---|---|
| **[저장소 개요 (아키텍처/기술 스택/특이점)](ComputerScience/Architecture/RottenNoble-Project.md)** | RottenNobleProject · (개요 문서) | `RottenNoble-Project` | 완료 |
| [RottenNobleProject 아키텍처 이해하기](ComputerScience/Architecture/RottenNobleProject-Architecture.md) | RottenNobleProject · (직접 코드 학습 세션 기록, STUDY-nn 아님) | `RottenNoble-Project` | 완료 — 1~3회차로 종료, 개별 주제 문서로 이어짐 |
| [PHP](ComputerScience/WebDevelopment/PHP.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [MariaDB (와 mysqli)](ComputerScience/Database/MariaDB.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [Redis](ComputerScience/Infrastructure/Redis.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [CRA → Vite 마이그레이션](ComputerScience/WebDevelopment/CRA-vs-Vite.md) | RottenNobleProject · `STUDY-02` | `RottenNoble-Project` | 완료 |
| [JWT vs Redis 세션](ComputerScience/Security/JWT-vs-Redis-Session.md) | RottenNobleProject · `STUDY-01` | `RottenNoble-Project` | 완료 |
| [CORS](ComputerScience/Network/CORS.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [비밀번호 해싱 (bcrypt)](ComputerScience/Security/Password-Hashing.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [REST API 설계 (응답 봉투)](ComputerScience/WebDevelopment/REST-API-Design.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [HTTPS, Let's Encrypt, Mixed Content](ComputerScience/Network/HTTPS-and-Mixed-Content.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [자체 호스팅(NAS) vs 클라우드](ComputerScience/Infrastructure/Self-Hosting-vs-Cloud.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [React](ComputerScience/WebDevelopment/React.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [React Router (HashRouter)](ComputerScience/WebDevelopment/React-Router.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [Token Storage (localStorage vs 쿠키)](ComputerScience/Security/Token-Storage.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [SQL Injection](ComputerScience/Security/SQL-Injection.md) | RottenNobleProject · (시니어 리뷰 + 실제 스캔 사건, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [프런트엔드 코드 노출 (JS 난독화)](ComputerScience/Security/Frontend-Code-Exposure.md) | RottenNobleProject · (시니어 리뷰, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |

### 그래픽스 (특정 프로젝트 종속 없음)

| 주제 | 출처 | 관련 레포지토리 | 상태 |
|---|---|---|---|
| [톤 매핑(Tone Mapping)](ComputerScience/Graphics/Tone-Mapping.md) | 순수 학습 호기심 + 컴투스 TA실 발표 영상 | `-` | 완료 |
| [URP 블룸 최적화](ComputerScience/Graphics/URP-Bloom-Optimization.md) | 컴투스 TA실 발표 영상 | `-` | 완료 |
| [URP DOF 최적화](ComputerScience/Graphics/URP-DOF-Optimization.md) | 컴투스 TA실 발표 영상 | `-` | 완료 |
| [커스텀 TAA](ComputerScience/Graphics/Custom-TAA.md) | 컴투스 TA실 발표 영상(세션 하이라이트) | `-` | 완료 |

### URP_PostProcessing (`Post Process Data`에 실제로 참조된 개별 셰이더)

| 주제 | 출처 | 관련 레포지토리 | 상태 |
|---|---|---|---|
| **[URP_PostProcessing 개요 (전체 파이프라인/셰이더 지도)](ComputerScience/URP_PostProcessing/URP_PostProcessing.md)** | LUT PS 정리 중 카테고리 전체 조망 필요성 인식 | `-` | 학습 중 — 개별 셰이더 문서가 늘 때마다 갱신 |
| [LUT PS (Lut Builder Ldr/Hdr PS)](ComputerScience/URP_PostProcessing/LUT-PS.md) | Unity URP `Post Process Data` 디버깅 중 발견 | `-` | 완료 |
| Uber Post PS | `Post Process Data` 디버깅 중 발견, LUT PS와 함께 확인됨 | `-` | 학습 전 (추후 예정) |
| Bloom 관련 패스 | `Post Process Data` 디버깅 중 발견 | `-` | 학습 전 — 최적화 사례는 위 [URP 블룸 최적화](ComputerScience/Graphics/URP-Bloom-Optimization.md) 참고 |
| Depth Of Field 관련 패스 | `Post Process Data` 디버깅 중 발견 | `-` | 학습 전 — 최적화 사례는 위 [URP DOF 최적화](ComputerScience/Graphics/URP-DOF-Optimization.md) 참고 |
| Final Post PS | `Post Process Data` 디버깅 중 발견 | `-` | 학습 전 (추후 예정) |
