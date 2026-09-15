# Unity ECS Spawner, Pooling, Warm-up

---

- **카테고리**: Unity ECS, 로딩, 성능
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` `STUDY-03`
- [TD_Project ECS Warm-up](../Architecture/TD_Project-ECS-Warmup.md)

## 정의

Spawner는 “언제 어떤 prefab Entity를 활성화할지”를 결정하는 System 또는 데이터 계약이다. Pooling은 반복 생성·파괴 대신 미리 만든 Entity를 비활성 상태로 보관하고 재사용하는 방식이다. Warm-up은 SubScene streaming, Addressables, pool 준비, shader variant 같은 첫 사용 비용을 플레이 시작 전으로 옮기는 과정이다. 세 개는 함께 쓰이지만 같은 개념은 아니다.

## 요약

Spawner Entity와 실제 적 Entity를 구분해야 한다. Spawner 또는 BattleSession은 스폰 일정을 가진 제어 데이터이고, 적 prefab과 pool Entity는 실제 전투 단위다. pool이 있더라도 처음 pool을 채우는 생성 비용은 남는다. 그래서 Patch 또는 Lobby에서 `ready` 상태까지 준비하고, BattleSession을 시작할 때만 시뮬레이션 시간을 흐르게 한다.

## 상세

### 역할을 분리한다

| 역할 | 예시 데이터 | 수명 |
|---|---|---|
| BattleSession | stage, elapsed time, speed, paused | 전투 세션 |
| SpawnSchedule | 등장 시각, prefab 종류, 수량 | stage 설정 |
| Pool 상태 | 사용 가능 Entity, 목표 크기 | 공통 또는 stage |
| 실제 적 | transform, health, target, render data | spawn부터 recycle까지 |
| 요청 Entity | spawn·damage·despawn 명령 | 짧은 수명 |

“EnemySpawner Entity” 하나가 모든 것을 처리하면 session 관리와 실제 적의 상태가 섞인다. 실제 적의 사망은 recycle 요청을 만들고, pool System이 `Disabled` 상태로 되돌리며, spawn System은 사용 가능한 Entity를 꺼내 초기화한다. 이 흐름이 명확하면 적 종류가 늘어도 상태 수명이 섞이지 않는다.

### Pool의 핵심은 재사용 계약

Pool은 단순히 `Instantiate`를 줄이는 기법이 아니다. 재사용되는 Entity에 이전 전투의 Component가 남지 않도록 reset 계약을 정의해야 한다. 체력, target, velocity, lifetime, 버퍼 길이, enable 상태, render property 중 무엇을 spawn 때 설정하고 recycle 때 지울지 적는다.

`Disabled` Component는 pool Entity를 일반 query와 렌더 경로에서 제외하는 흔한 방법이다. spawn 시 Disabled를 제거하고 필요한 값을 설정하며, recycle 시 dynamic buffer를 비우고 transient tag를 제거한 뒤 Disabled를 다시 붙인다. 이 구조 변경도 ECB 경계에서 처리하거나, enableable Component를 활용해 빈번한 조합 이동을 줄이는 선택을 비교한다.

### Warm-up 완료 기준

첫 Entity가 생성되기까지의 지연은 단일 원인이 아니다. 아래 각 단계의 완료를 분리해야 한다.

| 단계 | 완료 의미 |
|---|---|
| Addressables | 필요한 asset handle이 로드됨 |
| SubScene | baked Entity scene과 prefab 참조를 query할 수 있음 |
| Pool | 목표 수의 Entity가 재사용 가능한 상태 |
| Shader | 필요한 variant 또는 render state 검증이 끝남 |
| Session | pause 해제 후 스폰 시간을 진행할 수 있음 |

`Addressables 완료 = 전투 시작 가능`으로 단순화하면 pool 생성이나 ECB 재생이 뒤늦게 일어날 수 있다. Patch UI는 `BattleSimulationSystem.IsWarmupComplete`처럼 ECS 내부의 실제 준비 신호를 기다려야 한다.

### pool 크기는 고정 정답이 없다

목표 크기는 한 화면 최대 동시 수, spike wave, 메모리 예산, prefab 종류별 비용을 기준으로 잡는다. 충분한 pool을 모든 종류에 최대치로 만들면 hitch는 줄지만 앱 시작 시간이 길어지고 메모리를 잡아먹는다. 공통 적·탄환은 Patch에서 준비하고, boss나 stage 전용 VFX는 해당 stage 로딩 중 준비하는 계층이 현실적이다.

pool이 부족할 때 정책도 필요하다. 추가 생성, 가장 오래된 개체 회수, spawn drop, 로딩 화면 연장 중 무엇을 할지 게임 디자인과 함께 정한다. 아무 정책 없이 pool 밖 Instantiate가 조용히 발생하면 성능 측정이 왜곡된다.

## 비교표

| 개념 | 해결하는 문제 | 해결하지 않는 문제 |
|---|---|---|
| Spawner | 언제 무엇을 쓸지 | 생성 비용 자체 |
| Pooling | 반복 생성·파괴 비용 | 첫 pool 생성 비용 |
| SubScene preload | bake된 Entity 데이터 준비 | session 초기화와 shader state |
| Shader warm-up | 첫 렌더 hitch 완화 | Entity pool 부족 |

## 질문

- **Q. Entity가 한 번 생성되면 이후 생성은 항상 괜찮은가?**
  A. 같은 prefab의 반복 Instantiate 비용은 보통 안정되지만, 새로운 archetype, pool 확장, 렌더 state, 메모리 pressure는 여전히 문제가 될 수 있다. 그래서 실제 기기에서 spike를 측정한다.

- **Q. 모든 적을 게임 시작 때 pool에 넣어야 하나?**
  A. 아니다. 공통적으로 자주 쓰는 것만 앱 시작에 준비하고, stage 전용·드문 boss는 stage preload로 나누는 편이 시작 시간과 메모리의 균형이 좋다.

## 실무

- pool acquire/release를 API 또는 Component 계약으로 한곳에 모은다.
- spawn 시간은 `BattleSession`이 `started` 상태가 되기 전까지 진행하지 않는다.
- pool reset 목록을 테스트한다. 재사용 100회 뒤 남는 tag, target, buffer를 검사하면 좋다.
- Warm-up은 profiler marker와 타깃 기기 측정으로 범위를 조정한다.

## 같이 보기

- [SubScene과 씬 스트리밍](./SubScene-Streaming.md)
- [DynamicBuffer 패턴](./DynamicBuffer-Patterns.md)
- [ECS와 Unity 렌더 파이프라인](./ECS-Render-Pipeline.md)
- [TD_Project ECS Warm-up](../Architecture/TD_Project-ECS-Warmup.md)

## 참고자료

- [Unity EntityCommandBuffer](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-entity-command-buffers.html)
- [Unity Scene streaming](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/streaming-scenes.html)
- [Unity shader prewarm](https://docs.unity.cn/Manual/shader-prewarm.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | TD_Project Patch warm-up과 pool 설계 |

