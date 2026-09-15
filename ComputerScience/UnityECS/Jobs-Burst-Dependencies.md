# Unity ECS Job, Burst, 의존성 관리

---

- **카테고리**: Unity ECS, 병렬 처리, 성능
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` 대량 적·탄환 simulation 목표
- [Unity Entities jobs](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-jobs.html)

## 정의

Job은 main thread 밖의 worker thread에서 실행하도록 예약하는 작업 단위이고, Burst는 그 Job 또는 Burst 호환 코드를 고성능 native code로 컴파일하는 기술이다. ECS가 있다고 Job이 자동 병렬화되는 것은 아니다. System이 어떤 Component를 읽고 쓰는지, Unity API나 managed 참조를 사용하는지, 다른 Job과 어떤 의존성이 있는지가 병렬 가능 범위를 결정한다.

## 요약

가장 안전한 시작점은 main thread에서 정확한 ECS 로직을 만들고, Profiler에서 반복 비용이 확인된 System만 Job화하는 것이다. Job에서 쓴 데이터를 다음 System이 읽으려면 dependency가 연결되어야 한다. 이를 무시하고 `Complete()`를 자주 호출하면 병렬성을 잃고, 무시한 채 접근하면 data race나 safety exception이 생긴다.

## 상세

### Job에 적합한 일과 부적합한 일

수천 Entity의 이동, lifetime 감소, 단순 target 거리 계산처럼 독립 데이터에 같은 연산을 반복하는 일은 좋다. 반면 GameObject API 호출, UI 갱신, Addressables 완료 대기, ScriptableObject 탐색, 파일 I/O는 managed 세계에 속하므로 Job 안에 넣지 않는다.

| 작업 | Job/Burst 적합성 | 이유 |
|---|---|---|
| 위치와 속도 갱신 | 높음 | 값 타입 Component 반복 처리 |
| 모든 적의 목표 거리 계산 | 높음 | 독립 계산으로 나누기 쉬움 |
| Entity Instantiate 요청 기록 | 높음 | parallel ECB 사용 가능 |
| GameObject Instantiate | 낮음 | UnityEngine managed API |
| UI Text 변경 | 낮음 | main thread UI API |
| SO에서 데이터 찾기 | 낮음 | authoring/managed 참조 |

### 읽기와 쓰기가 의존성을 만든다

두 Job이 같은 Component를 둘 다 읽는 것은 병렬일 수 있다. 한쪽이 쓰고 다른 쪽이 읽거나 쓰면 순서가 필요하다. ECS의 `state.Dependency`나 SystemAPI가 추적하는 의존성은 이 관계를 이어 준다. 직접 만든 `JobHandle`을 잃어버리면 이후 System이 안전한 시점을 알 수 없다.

`Complete()`는 “지금 당장 결과가 필요하다”는 경계에서만 쓴다. 예를 들어 managed UI로 값을 넘기거나, 즉시 EntityManager API로 결과를 읽어야 할 때는 필요할 수 있다. 하지만 습관적으로 매 System 끝에 Complete하면 worker thread가 끝날 때까지 main thread가 기다리므로 Job화 효과가 작아진다.

### ECB와 병렬 spawn

Job 안에서 Entity를 구조적으로 바꾸려면 parallel writer를 제공하는 ECB를 사용한다. 각 반복에 안정적인 sort key를 주고, ECB 재생 시점은 group의 Begin/End ECB System이 맡는다. Job에서 prefab Entity를 Instantiate 요청하고 필요한 Component를 세팅한 뒤, 다음 안전한 ECB 재생 지점에 실제 Entity가 나타나는 흐름이다.

이 지연은 버그가 아니라 계약이다. “이번 프레임에 spawn 요청을 썼으니 같은 Query에서 바로 찾을 수 있다”라고 가정하면 안 된다. 같은 프레임의 즉시 결과가 꼭 필요하다면, 구조 변경 대신 미리 pool에서 활성 상태를 바꾸는 설계가 더 나을 수 있다.

### Burst가 막히는 흔한 이유

Burst는 managed object, virtual dispatch가 필요한 polymorphism, 많은 UnityEngine API, string 처리 같은 코드를 다루지 못하거나 이점을 내기 어렵다. Burst 오류를 피하려고 전부 static 전역 데이터로 바꾸기보다, managed 입력을 main thread에서 값 타입 Component·BlobAsset으로 변환하고 계산 부분만 Job에 넘기는 경계를 만든다.

## 비교표

| 방식 | 장점 | 위험 |
|---|---|---|
| Main thread System | 디버깅과 Unity API 연동이 단순 | 대량 반복에서 CPU 병목 |
| Scheduled Job | worker thread 병렬 처리 | dependency 누락, 결과 시점 오해 |
| Burst Job | 높은 산술 처리 효율 | managed API를 사용할 수 없음 |
| 무조건 Complete | 결과 시점이 단순 | 병렬성·프레임 겹침 손실 |

## 질문

- **Q. System 하나가 Job 하나인가?**
  A. 아니다. System은 Job을 여러 개 예약하거나 main thread에서만 실행할 수 있다. System은 프레임의 책임 단위이고 Job은 실행 단위다.

- **Q. Job을 많이 쪼개면 더 빠른가?**
  A. 아니다. 아주 작은 Job을 과도하게 만들면 scheduling overhead와 dependency가 늘어난다. 처리량과 profiling 결과로 판단한다.

## 예시 코드

```csharp
[BurstCompile]
public partial struct LifetimeSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var deltaTime = SystemAPI.Time.DeltaTime;

        state.Dependency = new ReduceLifetimeJob
        {
            DeltaTime = deltaTime,
        }.ScheduleParallel(state.Dependency);
    }
}
```

예시의 핵심은 JobHandle을 `state.Dependency`에 다시 연결하는 점이다. 실제 Job 정의에서는 읽기와 쓰기 Component를 명시해야 한다.

## 실무

- 먼저 Entity Debugger와 Profiler로 대량 반복이 실제 병목인지 확인한다.
- Job에서 쓸 데이터는 blittable 값, Entity 참조, NativeContainer, BlobAsset 같은 형태로 경계를 만든다.
- `Complete()` 위치를 코드 리뷰에서 명시적으로 확인한다.
- Burst 사용 시 Editor에서만 통과시키지 말고 타깃 플랫폼 Development Build로 측정한다.

## 같이 보기

- [System과 프레임 생명주기](./System-Lifecycle.md)
- [DynamicBuffer 패턴](./DynamicBuffer-Patterns.md)
- [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md)

## 참고자료

- [Unity Entities jobs](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-jobs.html)
- [Unity Burst manual](https://docs.unity3d.com/Packages/com.unity.burst@latest)
- [Unity EntityCommandBuffer](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/systems-entity-command-buffers.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | 대량 적과 탄환 병렬 처리 학습 |

