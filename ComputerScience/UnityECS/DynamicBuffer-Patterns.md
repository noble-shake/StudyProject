# Unity ECS DynamicBuffer 패턴

---

- **카테고리**: Unity ECS, 데이터 구조, 성능
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` 전투 스폰·pool 설계 논의
- [Unity Dynamic buffers](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/components-buffer.html)

## 정의

`DynamicBuffer<T>`는 Entity마다 길이가 달라질 수 있는 값 타입 원소의 배열이다. 일반 Component가 Entity당 값 하나를 갖는다면, Buffer Component는 Entity당 0개 이상의 원소를 가진다. 길이가 작을 때는 chunk 내부 공간을 활용하고, 커지면 별도 메모리로 확장될 수 있다.

## 요약

Buffer는 `List<T>`를 ECS에 그대로 옮긴 대체품이 아니다. 많은 Entity가 매 프레임 서로 다른 길이로 grow·shrink하면 메모리 이동과 접근 비용이 생긴다. 반대로 소유자가 명확하고, 값 타입 원소이며, 길이 변화가 제한된 데이터에는 매우 적합하다. “한 전투 세션의 스폰 일정”, “한 유닛의 짧은 waypoint 목록”, “한 발사체의 소수 히트 대상”처럼 **Entity가 소유하는 가변 데이터**에 쓴다.

## 상세

### Buffer Element 설계

원소는 `IBufferElementData`를 구현한다. 원소 하나의 크기는 작고 직렬화하기 쉬운 값으로 유지한다. Entity 참조와 숫자, 시간, 작은 enum은 좋지만, managed 객체, string, ScriptableObject 참조는 넣지 않는다.

```csharp
public struct SpawnScheduleElement : IBufferElementData
{
    public float Time;
    public Entity Prefab;
    public int Count;
}
```

위 Buffer는 `BattleSession` Entity가 소유할 수 있다. System은 현재 index를 별 Component에 두고, 시간이 지난 element만 읽어 spawn 요청을 만든다. 매 프레임 Buffer 앞부분을 `RemoveAt(0)`로 지우면 남은 원소를 계속 이동시킬 수 있으므로, 읽기 index를 증가시키고 세션이 끝날 때 정리하는 편이 흔히 낫다.

### InternalBufferCapacity는 측정값으로 정한다

`[InternalBufferCapacity(n)]`은 일정 길이까지 원소를 chunk 안에 두도록 힌트를 준다. n이 너무 크면 실제로 거의 비어 있는 Buffer까지 chunk 공간을 차지해 Entity density가 낮아진다. 너무 작으면 자주 외부 메모리로 나가게 된다. 평균 길이와 최대 길이를 Profiler로 보고 결정한다.

```csharp
[InternalBufferCapacity(8)]
public struct WaypointElement : IBufferElementData
{
    public float3 Position;
}
```

8은 마법의 숫자가 아니다. “대부분 3~6개이고 8개를 넘는 경우가 드물다”는 측정이 있을 때만 의미가 있다.

### Buffer와 다른 선택지

| 데이터 형태 | 우선 검토할 선택지 | 이유 |
|---|---|---|
| 모든 Entity가 고정 길이 값 | 여러 일반 Component | chunk 배치가 단순하다 |
| Entity별 짧고 가변적인 값 목록 | DynamicBuffer | 소유자와 수명이 명확하다 |
| 수천 Entity가 공유하는 읽기 전용 테이블 | BlobAsset | 중복 저장을 피한다 |
| 에디터에서 조정하는 설정 | ScriptableObject → bake | 런타임에 필요한 값만 변환한다 |
| 한 프레임짜리 요청 목록 | request Entity 또는 ECB | Buffer 수명보다 이벤트 경계가 명확하다 |

### 스폰 일정에 Buffer를 쓸 때의 함정

ScriptableObject에 stage 전체 스폰 정보를 두고 그것을 매 런타임 Entity에 복제하면 데이터 중복이 커질 수 있다. Stage 하나를 동시에 한 번만 플레이하고 일정이 읽기 전용이라면 BlobAsset이 더 적합할 수 있다. 반대로 진행 중에 특정 Entity가 일정을 수정하거나, 여러 독립 세션이 서로 다른 동적 명령을 쌓아야 한다면 Buffer가 자연스럽다.

따라서 “가변 길이니까 Buffer”가 아니라 다음을 먼저 묻는다.

1. 누가 이 목록을 소유하는가?
2. 실행 중 길이와 내용이 실제로 바뀌는가?
3. 동일 데이터가 많은 Entity에 중복되는가?
4. 원소를 Job에서 병렬로 읽고 쓸 필요가 있는가?

## 비교표

| 항목 | DynamicBuffer | BlobAsset | managed List |
|---|---|---|---|
| 런타임 수정 | 가능 | 불가 | 가능 |
| Job/Burst 친화성 | 높음 | 매우 높음 | 낮음 |
| 공유 읽기 전용 데이터 | 중복될 수 있음 | 적합 | 부적합 |
| Entity 수명 연동 | 자연스러움 | 별 참조 필요 | 객체 수명에 의존 |

## 질문

- **Q. Buffer를 쓰면 매번 GC가 없어지나?**
  A. managed `List<T>` 할당은 피할 수 있지만, buffer 확장과 structural change의 비용까지 사라지는 것은 아니다. 길이 변화 패턴을 측정해야 한다.

- **Q. Buffer 원소에 prefab Entity를 넣어도 되나?**
  A. 가능하다. 다만 prefab이 유효한 World와 bake 결과에 속하는지 보장해야 한다. Asset 원본 GameObject를 런타임 Buffer에 넣는 방식과는 다르다.

## 실무

- 매 프레임 앞에서 삭제하는 queue 패턴보다 cursor Component를 우선 검토한다.
- Buffer 하나에 서로 다른 책임의 데이터를 섞지 않는다. 예: 스폰 일정과 현재 결과 로그는 분리한다.
- Buffer 길이가 무제한으로 커질 수 있으면 상한, drop 정책, 소비 주기를 설계한다.
- 큰 정적 테이블은 Buffer를 복제하기 전에 BlobAsset 가능성을 확인한다.

## 같이 보기

- [Entity, Component, System](./Entity-Component-System.md)
- [Job, Burst, 의존성](./Jobs-Burst-Dependencies.md)
- [Authoring, Baker, ScriptableObject](./Baking-ScriptableObject.md)

## 참고자료

- [Unity Dynamic buffers](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/components-buffer.html)
- [Unity Blob assets](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/blob-assets.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS 전투 데이터 구조 설계 |

