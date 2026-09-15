# Unity ECS

Unity ECS를 처음 도입할 때 필요한 개념과, 실제 프로젝트에서 병목이 생기기 쉬운 지점을 주제별로 나눈 학습 지도다. `TD_Project` 문서는 이 원칙을 적용한 사례이고, 이 폴더는 특정 프로젝트에 묶이지 않는 재사용 가능한 개념을 다룬다.

## 읽는 순서

1. [Entity, Component, System](./Entity-Component-System.md) — 데이터와 로직을 왜 분리하는지
2. [System과 프레임 생명주기](./System-Lifecycle.md) — 어느 System이 언제 실행되는지
3. [ECS와 Unity 렌더 파이프라인](./ECS-Render-Pipeline.md) — Entities Graphics와 URP의 경계
4. [DynamicBuffer 패턴](./DynamicBuffer-Patterns.md) — 가변 길이 데이터를 안전하게 다루는 방법
5. [Job, Burst, 의존성](./Jobs-Burst-Dependencies.md) — 병렬화할 수 있는 코드의 경계
6. [SubScene과 씬 스트리밍](./SubScene-Streaming.md) — 베이킹 결과와 여러 SubScene의 역할
7. [Authoring, Baker, ScriptableObject](./Baking-ScriptableObject.md) — 편집용 데이터가 런타임 데이터가 되는 과정
8. [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md) — 전투 시작 hitch를 로딩 구간으로 옮기는 방법

## 이 폴더와 TD_Project의 관계

| 이론 문서 | TD_Project 적용 사례 |
|---|---|
| System과 프레임 생명주기 | `BattleSimulationSystem`, `BattleSession` |
| SubScene과 씬 스트리밍 | Patch Scene의 `PersistentSubSceneAnchor` |
| Authoring, Baker, ScriptableObject | `BattleSessionAuthoring`, `BattleSpawnConfigSO` |
| Spawner, Pool, Warm-up | Patch Addressables, Entity prefab pool |
| ECS와 Unity 렌더 파이프라인 | Entities Graphics prefab 렌더링 |

## 기준과 주의점

이 문서는 Entities 1.x 계열과 Unity 6에서 통용되는 원칙을 기준으로 작성했다. 패키지의 세부 API와 렌더링 지원 범위는 Entities 및 Entities Graphics 버전에 따라 바뀔 수 있으므로, 새 프로젝트에서는 패키지 버전의 공식 매뉴얼을 함께 확인한다.

## 같이 보기

- [TD_Project ECS 코어 루프](../Architecture/TD_Project.md)
- [TD_Project ECS Warm-up](../Architecture/TD_Project-ECS-Warmup.md)

