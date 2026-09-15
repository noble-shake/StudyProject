# Unity ECS SubScene과 여러 Scene의 스트리밍

---

- **카테고리**: Unity ECS, 씬 관리, 로딩
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` Patch Scene과 Persistent SubScene warm-up 설계
- [Unity Scene streaming](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/streaming-scenes.html)

## 정의

SubScene은 GameObject authoring을 Entity Scene으로 bake하고, 런타임에 Entity Scene을 비동기 streaming할 수 있게 하는 Unity 편집 단위다. SubScene이 많다고 ECS가 더 빠른 것은 아니다. 어떤 데이터가 함께 로드·언로드되어야 하는지, 어느 팀원이 무엇을 편집하는지, 메모리와 로딩 경계를 어떻게 둘지에 따라 분리한다.

## 요약

전투 규칙과 스폰 System은 여러 stage에서 재사용할 수 있으므로 보통 공통 코드와 하나의 BattleSession 흐름에 둔다. 반면 stage별 맵 배치, 고유한 대량 prefab 세트, 장기 체류하지 않는 환경 데이터는 별 SubScene으로 streaming하는 이유가 있다. SubScene 간에는 자동으로 “간섭”하는 관계가 없고, Entity 참조·공유 singleton·System query가 실제 연결을 만든다.

## 상세

### SubScene 로딩은 비동기이고 독립 단계가 있다

Entity Scene loading은 stall을 피하기 위해 비동기 streaming으로 동작한다. 따라서 “SubScene load 요청”, “Entity Scene 데이터가 World에 준비됨”, “Spawner가 prefab을 발견함”, “pool이 원하는 수만큼 준비됨”은 서로 다른 완료 지점이다.

Patch에서 pre-load할 때는 이 단계를 상태로 분리한다.

```text
requested  SubScene streaming 요청을 보냈다
loaded     필요한 Entity와 prefab 참조를 Query할 수 있다
ready      pool과 필수 런타임 준비가 끝났다
started    BattleSession 시간이 흐르고 스폰을 시작한다
```

로딩 화면은 `ready`까지 기다려야 전투 첫 프레임 hitch를 숨길 수 있다. 반대로 stage 전체의 모든 적을 pre-spawn하는 것은 시작 시간과 메모리를 과도하게 늘릴 수 있으므로 pool 목표량으로 제한한다.

### 여러 SubScene을 둘 때

| 분리 후보 | 별 SubScene이 유리한 이유 |
|---|---|
| Stage 맵·배경 배치 | 스테이지 전환과 함께 교체할 수 있다 |
| Stage 전용 대형 적·VFX prefab | 해당 stage에만 쓰는 메모리를 늦게 준비한다 |
| 공통 전투 prefab·Baker 설정 | Patch에서 한 번 준비하고 오래 유지한다 |
| 네비게이션·구역 데이터 | 섹션 단위 streaming 경계가 명확하다 |
| UI·카메라·라이팅 | 일반 Scene/Additive Scene이 더 자연스러운 경우가 많다 |

“stage마다 SubScene 하나”는 기본 규칙이 아니다. 모든 stage가 같은 적 prefab, 같은 spawn logic, 같은 규칙을 쓴다면 스테이지를 나눠도 공통 battle SubScene을 하나만 유지할 수 있다. 맵 배경·라이팅은 일반 Additive Scene으로, 대량 Entity 배치는 SubScene으로 혼합하는 것도 자연스럽다.

### Descriptor는 언제 필요한가

여러 Scene이 있을 때 Descriptor는 Scene 이름을 늘어놓는 목록이 아니라, **어떤 로딩 단위가 무엇을 제공하고 무엇이 준비되면 다음 단계로 갈 수 있는지**를 선언하는 계약이다. 예를 들어 StageDescriptor가 map scene key, battle SubScene key, stage spawn config, preload labels를 가진다면 Patch와 BattleSession은 하드코딩된 stage 이름을 몰라도 된다.

단일 SubScene과 단일 stage로 시작하는 동안에는 Descriptor를 과도하게 일반화할 필요가 없다. stage 선택, DLC, 분기 맵, 다양한 preload 구성이 실제 요구가 될 때 도입한다.

### 일반 Scene의 라이팅과 ECS Entity

Additive Scene이 URP의 Light, Volume, Camera 구성을 제공하고 SubScene의 Entity가 mesh·material을 제공할 수 있다. 둘은 같은 렌더 프레임에서 만난다. map interaction이 전혀 없는 단순 배경이라도, 라이팅·post process·reflection environment를 교체하려면 일반 Scene 분리가 유용할 수 있다.

## 비교표

| 선택 | 적합한 경우 | 주의점 |
|---|---|---|
| 단일 공통 SubScene | 작은 프로젝트, 공통 전투 prefab | 모든 stage 리소스가 오래 남을 수 있음 |
| 공통 + stage SubScene | stage별 대형 Entity·배치가 다름 | 로딩 상태와 참조 경계 관리 필요 |
| 일반 Additive Scene | UI, 카메라, 라이팅, GameObject 맵 | ECS data preload와 완료 기준은 별도 |
| Descriptor | 로딩 조합이 여러 개 | 단순 프로젝트에 과한 추상화 금지 |

## 질문

- **Q. SubScene을 한 번 load하면 이후 적 생성은 공짜인가?**
  A. 아니다. bake된 prefab 참조가 준비되어도 Instantiate, 초기화, 렌더 state와 pool 부족 시의 추가 생성 비용은 남는다. 그래서 pool warm-up을 별 단계로 본다.

- **Q. SubScene끼리 서로 영향을 주나?**
  A. 같은 World에 streaming되면 System query가 양쪽 Entity를 함께 처리할 수 있다. 영향은 SubScene이라는 파일 경계가 아니라 shared Component, Entity reference, singleton 설계에서 생긴다.

## 실무

- 로딩 완료를 Scene API 콜백 하나로 판단하지 말고, 실제 gameplay 준비 조건을 상태로 모델링한다.
- stage 전환 때 유지할 공통 pool과 버릴 stage 전용 pool을 분리한다.
- Scene을 세분화하기 전에 메모리, 편집 충돌, 로딩 UX 중 무엇을 해결하려는지 한 줄로 적는다.
- SubScene 스트리밍 중 System이 빈 query를 정상 상태로 처리하도록 만든다.

## 같이 보기

- [System과 프레임 생명주기](./System-Lifecycle.md)
- [Authoring, Baker, ScriptableObject](./Baking-ScriptableObject.md)
- [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md)

## 참고자료

- [Unity Scene streaming](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/streaming-scenes.html)
- [Unity SubScenes](https://docs.unity.cn/Packages/com.unity.entities@1.2/manual/conversion-subscenes.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | Patch preload와 stage 구성 설계 |

