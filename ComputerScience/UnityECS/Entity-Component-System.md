# Unity ECS의 Entity, Component, System

---

- **카테고리**: Unity ECS, 게임 아키텍처
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` `STUDY-01`, `STUDY-02`
- [Unity Entities 개요](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/intro-to-entities.html)

## 정의

ECS는 게임 오브젝트 하나에 데이터와 동작을 함께 넣는 대신, **데이터는 Component에**, **동작은 System에**, **데이터 묶음의 정체성은 Entity에** 둔다. Entity는 이름이나 메서드를 가진 객체가 아니라, 어떤 Component들이 함께 속하는지를 가리키는 가벼운 식별자다.

예를 들어 적 하나는 `LocalTransform`, `Health`, `MoveSpeed`, `EnemyTag`를 가진 Entity가 된다. 이동 규칙은 적 안에 들어 있지 않고, `LocalTransform`과 `MoveSpeed`를 가진 모든 Entity를 한 번에 조회하는 `MovementSystem`에 있다. 같은 Entity가 체력 Component도 가지면 `DamageSystem`도 그 Entity를 처리한다.

## 요약

ECS의 성능 이점은 Entity라는 이름표 자체가 아니라, **같은 Component 조합을 가진 데이터를 연속된 메모리 구조로 다루고 System이 그 묶음을 순차 처리할 수 있는 점**에서 나온다. 그래서 ECS를 쓸 때 중요한 질문은 “이 클래스에 무슨 메서드를 넣을까?”가 아니라 “어떤 데이터가 함께 읽히고, 어떤 System이 그것을 바꿀까?”다.

## 상세

### Entity는 컨테이너가 아니라 조합의 키다

GameObject는 Transform, MonoBehaviour, Renderer처럼 서로 다른 성격의 객체를 계층으로 묶는다. 반면 Entity는 Component 타입 조합으로 분류된다. Unity ECS는 같은 조합을 가진 Entity를 archetype 단위로 정리하고, 그 안에서 Component 데이터를 chunk에 저장한다.

따라서 `EnemyTag`를 붙이거나 제거하는 일은 단순 bool 변경보다 비용이 클 수 있다. Component 조합이 바뀌어 다른 archetype으로 옮겨가는 **structural change**이기 때문이다. 매 프레임 반복되는 상태는 `bool IsDead` 같은 데이터로 표현하고, 정말 조회 대상 자체를 바꾸어야 할 때만 Tag 추가·제거나 `Disabled`를 사용한다.

### Component는 상태만 표현한다

`IComponentData`에는 보통 값 타입 데이터만 둔다. `Health`, `Cooldown`, `TargetEntity`, `MoveSpeed`처럼 System이 읽고 쓰는 현재 상태가 대상이다. Component에 `TakeDamage()` 같은 메서드나 managed 참조를 넣기 시작하면 데이터 병렬 처리와 Burst의 이점을 잃고, 의존 관계도 다시 객체 중심으로 굳어진다.

의미별로는 다음처럼 나눈다.

| 종류 | 역할 | 예시 |
|---|---|---|
| 데이터 Component | 변화하는 상태 | `Health`, `Velocity`, `Lifetime` |
| Tag Component | 조회 분류 | `EnemyTag`, `DeadTag` |
| Shared Component | 같은 값끼리 분리할 때 | 드문 렌더 또는 그룹 분류 |
| Buffer Component | Entity마다 가변 길이 데이터 | 경로 점, 피격 이력 |
| Enableable Component | 구조 변경 없이 on/off | `IEnableableComponent` 상태 |

### System은 한 책임의 데이터 변환이다

System은 EntityQuery로 필요한 Component 조합만 선택하고, 한 프레임의 상태를 다음 상태로 바꾼다. “적 AI System”처럼 광범위하게 시작할 수는 있지만, 내부에 탐색·이동·공격·사망·드랍까지 쌓이면 읽기와 쓰기 의존성이 엉켜 Job화와 순서 제어가 어려워진다.

좋은 분리는 데이터 흐름으로 판단한다. `TargetSelectionSystem`이 `TargetEntity`를 쓰고, `SteeringSystem`이 그것을 읽어 `Velocity`를 쓰고, `MovementSystem`이 `LocalTransform`을 쓴다면 순서와 책임이 드러난다. 이 방식은 CQRS와도 닿아 있다. 읽기 중심 계산과 상태 변경을 별 System으로 분리하되, 각 System을 억지로 Command/Query라는 이름으로 나누기보다 **Component 읽기·쓰기 경계**가 명확한지를 우선한다.

## 비교표

| 관점 | MonoBehaviour 중심 | ECS 중심 |
|---|---|---|
| 행동 위치 | 객체 인스턴스 메서드 | System |
| 상태 위치 | 객체 필드 | Component |
| 다수 처리 | 객체를 하나씩 호출 | Query로 같은 데이터 묶음 처리 |
| 상호 참조 | 직접 객체 참조가 쉬움 | Entity 참조와 명시적 데이터 흐름 |
| 적합한 영역 | UI, 고유한 연출, 소수 객체 | 대량·반복 시뮬레이션 |

## 질문

- **Q. Entity 하나가 곧 적 한 마리인가?**
  A. 보통 그렇지만 필수는 아니다. 적의 본체, 렌더 proxy, 이벤트 요청 Entity를 분리할 수도 있다. 중요한 것은 GameObject와 1:1로 맞추는 것이 아니라 데이터 수명과 처리 규칙이다.

- **Q. 모든 코드를 ECS로 옮겨야 하나?**
  A. 아니다. UI, 카메라 연출, 플랫폼 SDK처럼 managed 객체와 Unity API 의존이 큰 영역은 MonoBehaviour가 더 자연스럽다. ECS는 반복 시뮬레이션 경계에서 가장 효율적이다.

## 예시 코드

아래에서 이동 Component는 상태만, System은 그 상태의 변환만 담당한다.

```csharp
public struct MoveSpeed : IComponentData
{
    public float Value;
}

public partial struct MovementSystem : ISystem
{
    public void OnUpdate(ref SystemState state)
    {
        var deltaTime = SystemAPI.Time.DeltaTime;

        foreach (var transform in SystemAPI
                     .Query<RefRW<LocalTransform>>()
                     .WithAll<MoveSpeed>())
        {
            transform.ValueRW.Position += transform.ValueRO.Forward() * deltaTime;
        }
    }
}
```

실전에서는 `MoveSpeed`도 함께 Query로 읽고, Job을 쓸 수 있는 형태로 확장한다. 예시는 역할 분리만 보이기 위한 최소 형태다.

## 실무

- Component는 “누가 소유하는 객체인가”보다 “누가 같은 시점에 읽고 쓰는 데이터인가”로 나눈다.
- 매 프레임 붙였다 뗄 Tag를 늘리기 전에 enableable Component나 상태값으로 해결 가능한지 확인한다.
- Entity마다 managed class나 `List<T>`를 넣으면 chunk 배치, Burst, Job 병렬 처리의 이점이 줄어든다.
- System 이름은 도메인 명사보다 변환 동사를 드러내면 책임이 잘 보인다. 예: `ResolveDamageSystem`, `RecycleExpiredProjectileSystem`.

## 같이 보기

- [System과 프레임 생명주기](./System-Lifecycle.md)
- [DynamicBuffer 패턴](./DynamicBuffer-Patterns.md)
- [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md)

## 참고자료

- [Unity Entities 개념](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/intro-to-entities.html)
- [Unity Entities 시스템 개요](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-overview.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | TD_Project ECS 도입 맥락 |

