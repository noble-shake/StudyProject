# Unity ECS System과 프레임 생명주기

---

- **카테고리**: Unity ECS, 게임 루프
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` `STUDY-02`
- [Unity System groups](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-update-order.html)

## 정의

ECS System은 “프로그램이 한 프레임마다 전부 실행된다”는 뜻이 아니다. System은 World에 생성되고, 지정된 SystemGroup에 들어가며, 그룹의 업데이트 순서가 왔고 실행 조건을 만족할 때 `OnUpdate`를 수행한다. Query가 비어 있거나 `RequireForUpdate` 조건이 만족되지 않으면 해당 프레임에는 실행하지 않을 수 있다.

## 요약

Unity PlayerLoop의 큰 단계 안에 ECS의 `InitializationSystemGroup`, `SimulationSystemGroup`, `PresentationSystemGroup`이 들어간다. 게임 규칙은 보통 Simulation에 두고, 프레임 마지막 렌더 준비와 맞닿는 처리는 Presentation의 제약을 이해한 뒤 넣는다. System의 생성 순서와 업데이트 순서는 서로 다른 문제다.

## 상세

### World와 SystemGroup

World는 EntityManager와 System 집합을 가진 실행 공간이다. 기본 게임 World가 있어도, 테스트·Netcode·에디터 도구는 별 World를 만들 수 있다. SystemGroup은 System을 계층적으로 묶어 정렬한다. 최상위 기본 그룹은 다음 세 가지다.

| 그룹 | PlayerLoop에서의 성격 | 주 용도 |
|---|---|---|
| Initialization | 프레임 초기화 구간 | 이전 프레임 결과 정리, 입력 수집 |
| Simulation | 게임 Update 구간 | 전투, 이동, 충돌 후 규칙, 스폰 |
| Presentation | 렌더 직전 구간 | 표시용 데이터 준비 |

`[UpdateInGroup]`으로 소속을 명시하고, 같은 그룹의 직접 자식 사이에서만 `[UpdateBefore]`, `[UpdateAfter]`로 순서를 정한다. 모든 System에 전역 순번을 붙이는 방식보다, 도메인 그룹을 먼저 분리한 뒤 필요한 의존성만 선언하는 편이 유지보수에 유리하다.

### 생성과 업데이트는 구분한다

`OnCreate`는 System 인스턴스가 World에 만들어질 때 한 번 호출된다. Component lookup, query, singleton 요구 조건 같은 준비를 둔다. `OnStartRunning`은 System이 실제 업데이트를 시작하거나 다시 시작할 때 호출된다. `OnUpdate`는 조건이 만족하는 매 프레임 실행되고, `OnStopRunning`은 조건이 더 이상 맞지 않아 멈출 때 호출된다. World가 dispose되면 `OnDestroy`가 호출된다.

이 차이는 SubScene 로딩과 특히 관계가 크다. SubScene Entity가 아직 없을 때 `OnCreate`가 호출되는 것은 정상이다. “SpawnConfig Entity가 존재할 때만 실행”하도록 `state.RequireForUpdate<BattleSession>()`를 걸면, SubScene이 준비되기 전에는 `OnUpdate`가 건너뛰어진다. 로딩 완료는 `OnCreate` 호출 여부가 아니라, 필요한 singleton·pool 상태·Addressables 상태를 함께 확인해서 판단한다.

### ECB가 필요한 이유

Component 추가와 제거, Instantiate, Destroy 같은 structural change는 Query 순회나 병렬 Job 안에서 즉시 수행하면 안전하지 않다. `EntityCommandBuffer`에 명령을 쌓고 해당 ECB System이 정해진 시점에 재생하게 만든다. ECB는 “아무 때나 쓰는 비동기 큐”가 아니라 **프레임 순서 안에 명시된 구조 변경 경계**다.

예를 들어 Damage System은 `DeadTag`를 직접 붙이지 않고 EndSimulation ECB에 기록할 수 있다. 이후 정리 System은 다음 적절한 경계에서 `DeadTag`를 조회한다. 같은 프레임에 반드시 볼 필요가 있다면 System 순서와 ECB 재생 지점을 설계해야 하며, 무심코 sync point를 늘리지 않는다.

## 비교표

| 질문 | 답 |
|---|---|
| 모든 System이 매 프레임 실행되나 | 아니다. enabled, group, query 조건을 만족해야 한다. |
| `OnCreate`가 끝나면 SubScene도 준비됐나 | 아니다. System 생성과 Entity scene streaming은 별개다. |
| `UpdateAfter`는 어디에나 쓸 수 있나 | 같은 SystemGroup의 직접 자식 관계에서 쓴다. |
| ECB는 왜 쓰나 | 순회·Job 중 구조 변경을 지연하고 안전한 재생 지점을 만들기 위해서다. |

## 질문

- **Q. System을 CQRS처럼 CommandSystem과 QuerySystem으로 나누면 좋은가?**
  A. 명칭보다 실제 읽기·쓰기 경계가 중요하다. 계산 결과만 만들고 다음 System이 소비하는 흐름은 좋지만, 단순 조회를 위해 Entity를 새로 만들거나 과도한 이벤트 Component를 만들면 구조 변경과 순서 문제가 늘어난다.

- **Q. Pause는 `Time.timeScale = 0`이면 충분한가?**
  A. ECS System이 어떤 시간 소스를 읽는지에 따라 다르다. 전투 Simulation만 멈추려면 `BattleSession`의 DeltaTime 또는 System 활성 조건을 제어하고 UI·로딩은 계속 실행하도록 분리하는 편이 의도를 명확히 한다.

## 예시 코드

```csharp
[UpdateInGroup(typeof(SimulationSystemGroup))]
[UpdateAfter(typeof(TargetSelectionSystem))]
public partial struct SteeringSystem : ISystem
{
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<BattleSession>();
    }

    public void OnUpdate(ref SystemState state)
    {
        // BattleSession이 존재하는 프레임에만 실행한다.
    }
}
```

## 플로우차트

[`System-Lifecycle.flow.md`](./System-Lifecycle.flow.md)

## 실무

- `OnCreate`에서 실제 씬 데이터가 있다고 가정하지 않는다.
- 그룹에는 정렬 책임만 두고, 게임 로직은 별 System에 둔다.
- 시스템 순서 문제를 발견하면 먼저 “어떤 Component를 누가 쓰고 읽는가”를 적는다.
- `Window > Entities > Systems`로 실제 World의 그룹·순서를 확인한다. 코드의 attribute만 보고 추측하지 않는다.

## 같이 보기

- [Entity, Component, System](./Entity-Component-System.md)
- [Job, Burst, 의존성](./Jobs-Burst-Dependencies.md)
- [SubScene과 씬 스트리밍](./SubScene-Streaming.md)

## 참고자료

- [Unity System groups](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-update-order.html)
- [Unity Systems window](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/editor-systems-window.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS 시스템 순서와 BattleSession 설계 논의 |

