# Unity ECS Authoring, Baker, ScriptableObject

---

- **카테고리**: Unity ECS, 데이터 변환, ScriptableObject
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` `BattleSessionAuthoring`, `BattleSpawnConfigSO`
- [Unity Baking overview](https://docs.unity.cn/Packages/com.unity.entities@1.1/manual/baking-overview.html)

## 정의

Authoring은 Inspector에서 사람이 편집하기 좋은 GameObject, MonoBehaviour, ScriptableObject 형태의 데이터다. Baker는 그 authoring을 읽어 런타임에 필요한 Entity와 Component로 변환한다. 이 변환을 baking이라고 한다. 런타임 ECS가 ScriptableObject를 직접 매 프레임 탐색하는 대신, 필요한 값과 Entity prefab 참조만 Component 또는 BlobAsset으로 옮기는 이유는 편집 유연성과 실행 효율의 책임을 분리하기 위해서다.

## 요약

ScriptableObject는 ECS에서 금지 대상이 아니다. **에디터 설정의 원본**으로는 매우 좋다. 문제는 runtime hot path에서 managed ScriptableObject 객체를 계속 읽고, 그 안의 List와 UnityEngine.Object 참조를 대량 Entity가 반복적으로 따라가는 방식이다. Baker는 SO를 검증하고 필요한 값만 unmanaged runtime data로 평탄화하는 경계다.

## 상세

### 세 데이터 층

| 층 | 목적 | 예 |
|---|---|---|
| Authoring | 사람이 Inspector에서 조정 | `BattleSessionAuthoring`, `BattleSpawnConfigSO` |
| Baked runtime data | System이 빠르게 조회 | `BattleSession`, prefab Entity reference |
| Mutable session state | 실제 플레이 중 변함 | 현재 wave index, elapsed time, pool 사용량 |

이 구분에서 같은 “스폰 설정”이라도 자리가 달라진다. 등장 시각과 prefab 종류처럼 stage 시작 후 바뀌지 않는 값은 baked 읽기 전용 데이터가 된다. 현재 몇 번째 항목까지 소비했는지는 `SpawnCursor` 같은 mutable Component가 된다. ScriptableObject 원본은 Editor에서 수정하고 다시 bake할 때만 관여한다.

### Baker가 해야 할 일

Baker는 UnityEngine.Object를 다루는 안전한 장소다. authoring의 prefab을 `GetEntity`로 Entity prefab 참조로 바꾸고, 숫자와 enum을 Component에 담는다. 필요한 authoring 의존성을 등록해 Inspector 값이 변했을 때 bake 결과가 갱신되도록 해야 한다.

SO 목록이 작고 stage마다 한 번만 쓰이면 DynamicBuffer로 element를 bake할 수 있다. 여러 stage·여러 Entity가 같은 큰 읽기 전용 테이블을 공유하면 BlobAsset으로 한 번 생성해 참조하는 편이 더 적합할 수 있다. 어떤 선택이든 System은 SO가 아니라 baked data만 읽는 것이 목표다.

### managed와 unmanaged의 실제 경계

unmanaged Component는 값 타입이며 Burst와 Job에서 다루기 좋다. managed Component와 `SystemBase`가 항상 나쁜 것은 아니다. UI bridge, analytics, Addressables 완료 결과처럼 managed API를 만나는 작은 경계에는 필요할 수 있다. 다만 전투의 매 프레임 핵심 loop가 managed reference를 따라가면 대량 처리의 장점이 줄어든다.

SO를 Entity에 직접 참조시키는 방식은 “한 번만 읽는 session bootstrap”에서는 실용적일 수 있지만, 그 Entity를 Burst Job이 접근할 수 있는 고성능 데이터라고 착각하면 안 된다. runtime lookup을 별 main-thread System에 제한하고 결과를 unmanaged Component에 복사하는 식으로 경계를 명시한다.

### 변경 대응

에디터에서 SO를 바꾸면 baking 결과가 변하지만, 이미 실행 중인 player build의 Entity 데이터가 즉시 갱신되는 것은 아니다. Live tuning이 필요하다면 Addressables remote content, 서버 데이터, 별 runtime config Entity 같은 운영 경로를 설계해야 한다. “SO 값 변경이 게임에 바로 반영된다”는 editor 경험을 release build에 그대로 기대하지 않는다.

## 비교표

| 선택 | 편집성 | 런타임 성능 | 적합한 데이터 |
|---|---|---|---|
| ScriptableObject 직접 접근 | 높음 | hot path에는 낮음 | bootstrap, managed bridge |
| IComponentData | 중간 | 높음 | 작고 자주 변하는 상태 |
| DynamicBuffer | 중간 | 높음 | Entity별 가변 길이 값 |
| BlobAsset | bake 필요 | 매우 높음 | 큰 공유 읽기 전용 데이터 |

## 질문

- **Q. Stage spawn 정보는 무조건 BlobAsset이어야 하나?**
  A. 아니다. stage 하나의 짧은 일정, 한 session만의 데이터라면 buffer가 읽기 쉽다. 같은 큰 표를 많은 Entity가 공유하거나 복제를 피해야 할 때 BlobAsset의 장점이 커진다.

- **Q. SO를 쓰면 ECS 최적화가 무효가 되나?**
  A. 아니다. SO를 authoring source로 쓰고 bake 결과만 simulation에서 읽으면 자연스러운 ECS workflow다.

## 예시 코드

```csharp
public sealed class BattleSessionAuthoring : MonoBehaviour
{
    public BattleSpawnConfigSO SpawnConfig;
}

public sealed class BattleSessionBaker : Baker<BattleSessionAuthoring>
{
    public override void Bake(BattleSessionAuthoring authoring)
    {
        var entity = GetEntity(TransformUsageFlags.None);
        var buffer = AddBuffer<SpawnScheduleElement>(entity);

        foreach (var entry in authoring.SpawnConfig.Entries)
        {
            buffer.Add(new SpawnScheduleElement
            {
                Time = entry.Time,
                Prefab = GetEntity(entry.Prefab, TransformUsageFlags.Dynamic),
                Count = entry.Count,
            });
        }
    }
}
```

이 예시는 SO를 bake 시점에만 읽고, runtime System은 `SpawnScheduleElement`만 읽도록 만드는 경계를 보여 준다.

## 실무

- SO에는 디자이너가 편집할 의미 있는 이름과 검증 가능한 범위를 둔다.
- Baker에서 null prefab, 음수 수량, 시간 역순 같은 오류를 가능한 일찍 검증한다.
- runtime System에서 `Resources.Load`, SO 검색, GameObject 탐색을 하지 않는다.
- 큰 설정 데이터는 복제량과 접근 빈도를 측정한 뒤 Buffer와 BlobAsset 중 선택한다.

## 같이 보기

- [DynamicBuffer 패턴](./DynamicBuffer-Patterns.md)
- [SubScene과 씬 스트리밍](./SubScene-Streaming.md)
- [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md)

## 참고자료

- [Unity Baking overview](https://docs.unity.cn/Packages/com.unity.entities@1.1/manual/baking-overview.html)
- [Unity Bakers](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/baking-baker-overview.html)
- [Unity Blob assets](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/blob-assets.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | BattleSpawnConfigSO bake 구조 |

