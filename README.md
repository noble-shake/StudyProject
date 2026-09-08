# StudyProject

> **세션을 시작하면 먼저 `DevelopPrompt`를 본다.** 이 저장소 자체엔 규칙이 없다 — 이 저장소가 어떻게
> 쓰이는지의 정책은 `DevelopPrompt/POLICY/STUDY.md`("StudyProject 연동" 절)에 있고, "왜 이 주제가
> 궁금해졌는지"의 배경은 `DevelopPrompt/CurrentProject/_{프로젝트명}/Study.md`의 각 `STUDY-nn` 항목에
> 있다. 여기 문서만 보고 시작하지 않는다.

Study with DevelopPrompt — 여러 프로젝트에서 궁금해졌던 것(각 프로젝트의 `Study.md` 백로그)을 실제로 파고들어 공부한 내용을 쌓는 저장소입니다.

각 프로젝트의 `Study.md` 항목과 여기 내용을 서로 링크해서, "왜 궁금해졌는지"는 원래 프로젝트에, "실제로 무엇을 배웠는지"는 여기에 남깁니다.

## 구조

- 프로젝트별 폴더가 아니라 **주제 단위**로 정리한다 — 같은 주제가 여러 프로젝트에서 궁금해질 수
  있어서, 프로젝트별로 쪼개면 같은 내용이 흩어진다.
- 새 주제를 시작할 때 [`_TEMPLATE.md`](_TEMPLATE.md)를 복사해서 쓴다.
- 문서 상단엔 항상 어느 프로젝트의 어느 `STUDY-nn`에서 왔는지 백링크를 남긴다.
- 다 배우면 원본 `Study.md` 쪽 항목 상태를 "완료"로 바꾸고 결론 한 줄 + 이 저장소 문서 경로를
  덧붙인다(내용 자체는 `Study.md`로 복사하지 않는다 — 원본은 항상 여기 하나뿐).
- **문체가 `DevelopPrompt`와 다르다.** `DevelopPrompt`의 정책·`CODE_MEMO.md`는 AI 에이전트가 빠르게
  훑도록 압축한 컨텍스트 문서지만, 여기는 **사람이 읽고 배우는 교재**다. 개념을 실제로 설명하는
  문장으로 풀어 쓰고, 표는 비교·정리용으로만 쓴다 — 자세한 형식은 `_TEMPLATE.md` 참고.

## 항목 인덱스

| 주제 | 출처(프로젝트 · STUDY-nn) | 관련 레포지토리 | 상태 |
|---|---|---|---|
| [RottenNobleProject 아키텍처 이해하기](RottenNobleProject-Architecture.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 학습 중 — 코드 구조는 다 훑음, 아래 주제 문서들로 이어짐 |
| [PHP](PHP.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [MariaDB (와 mysqli)](MariaDB.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [Redis](Redis.md) | RottenNobleProject · (직접 코드 학습, STUDY-nn 아님) | `RottenNoble-Project` | 완료 |
| [CRA → Vite 마이그레이션](CRA-vs-Vite.md) | RottenNobleProject · `STUDY-02` | `RottenNoble-Project` | 완료 |
| [JWT vs Redis 세션](JWT-vs-Redis-Session.md) | RottenNobleProject · `STUDY-01` | `RottenNoble-Project` | 완료 |
