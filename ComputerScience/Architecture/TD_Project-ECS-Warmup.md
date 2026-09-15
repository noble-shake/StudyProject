# TD_Project ECS Warm-up — Addressables에서 Entity Pool까지

---

- **카테고리**: 아키텍처, 게임 개발, 그래픽스
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Unity 6 `6000.4.0b11` 목표 / Addressables 2.9.1
- **관련 레포지토리**: `TD_Project` (`noble-shake/TD_Project`)
- **엔진**: `Unity`
- **상위 문서**: `ComputerScience/Architecture/TD_Project.md`

---

## 출처

- `TD_Project`의 `DevelopPrompt/CurrentProject/_TD_Project/Study.md` — `STUDY-03`
- `DevelopPrompt/CurrentProject/_TD_Project/CODE_MEMO.md` — `MEMO-ECS-02`
- `TD_Project/Assets/Dev/Contents/Patch/PatchEntryPoint.cs`

## 정의

Warm-up은 플레이 도중 처음 사용되는 리소스와 실행 준비를 미리 끝내는 과정이다. Unity 프로젝트에서는
이 말이 하나의 작업을 가리키지 않는다. Addressables가 에셋과 의존성을 메모리에 올리는 일,
SubScene이 baked Entity scene을 스트리밍하는 일, ECS가 실제 풀 Entity를 생성하는 일, 셰이더가
그래픽 드라이버용 프로그램을 준비하는 일은 서로 다른 단계다.

따라서 “SubScene을 미리 로드했다”만으로는 “첫 전투 프레임이 끊기지 않는다”고 말할 수 없다.
각 단계가 끝났다는 신호를 나누고, 로딩 화면에서 필요한 단계만 기다려야 한다.

## 요약

현재 TD_Project의 Patch Warm-up은 Addressables 레이블 로드와 선택적 셰이더 Warm-up을 SubScene
스트리밍과 병렬로 시작하고, `BattleSimulationSystem.IsWarmupComplete`가 true가 될 때까지 기다린다.
시스템은 적 Entity를 미리 복제해 `Disabled` 풀로 보관한다. 이후 InGame에서는 스테이지를
Additive로 로드한 뒤 전투 세션만 시작한다.

이 방식은 첫 전투의 Instantiate 비용과 SubScene 생성 지연을 로딩 화면으로 옮기는 데는 효과적이다.
그러나 `ShaderVariantCollection.WarmUp()` 하나가 모든 플랫폼의 정확한 GPU Pipeline State Object를
보장하지는 않으므로, Vulkan·Metal·DX12에서는 실제 렌더 상태를 포함한 추가 검증이 필요하다.

## 상세

### 1. Addressables 로드

Patch의 `PatchEntryPoint`는 다음 세 레이블을 독립적인 선택 항목으로 취급한다.

| 레이블 | 현재 역할 | 기본 상태 |
|---|---|---|
| `ECS.Warmup` | ECS 적 프리팹과 의존성 로드 | 사용 |
| `Graphics.Warmup` | `ShaderVariantCollection` 로드 | 계약만 존재, 실제 에셋 등록 필요 |
| 폰트 레이블 | TMP Font Asset 로드 | 빈 문자열, 베이크/정적 아틀라스면 생략 |

Addressables의 레이블은 하나의 에셋 주소라기보다 여러 위치를 묶는 key로 사용할 수 있다.
프로젝트의 `ResourceFactory.LoadByLabelAsync<T>`는 이 레이블을 통해 필요한 타입의 에셋들을
비동기로 읽는다. 현재 코드는 ECS 프리팹, 셰이더 컬렉션, 폰트 로드를 `UniTask.WhenAll`로 시작해
서로 독립적인 I/O가 순차적으로 기다려지지 않게 한다.

중요한 점은 Addressables 로드 완료와 풀 생성 완료를 같은 상태로 기록하지 않는 것이다. 프리팹이
메모리에 있다는 것은 Baker가 만든 prefab Entity를 바탕으로 런타임 복제를 시작할 수 있다는
뜻일 뿐, 이미 복제된 적 Entity가 충분하다는 뜻은 아니다.

### 2. SubScene 스트리밍

Patch 씬에는 `PersistentSubSceneAnchor`와 Unity `SubScene` 컴포넌트가 함께 있다. SubScene의
`AutoLoadScene`이 켜져 있으므로 Patch가 살아 있는 동안 테스트 SubScene의 Entity scene을
스트리밍한다. 앵커 GameObject는 `DontDestroyOnLoad`로 유지되어 Title, Lobby, InGame으로 씬이
바뀌어도 이 검증용 SubScene이 바로 제거되지 않게 한다.

이 구성이 의미하는 것은 SubScene을 영원히 유지하자는 것이 아니다. 현재 목표가 “앱 시작 뒤
전투 진입 시 발생하는 첫 Entity 생성 지연을 관찰하고 줄이는 것”이므로 수명을 길게 잡은 것이다.
스테이지가 많아지면 공통 프리팹/풀을 Patch에서 준비할지, 스테이지별 맵과 세션을 InGame에서
로드할지 메모리와 전환 빈도를 기준으로 다시 결정한다.

### 3. Baker와 Entity 준비

`BattleSessionAuthoring`은 `BattleSpawnConfigSO`와 적 GameObject prefab을 참조한다.
`BattleSessionBaker`는 스폰 위치·간격·수량·속도·난수 시드를 검사하고, ScriptableObject를 직접
런타임에 들고 다니는 대신 `BattleSession`에 unmanaged 값과 Entity prefab 참조를 기록한다.

`BattleSimulationSystem`은 세션을 찾으면 아직 준비되지 않은 동안 `PoolSize`만큼 Entity를
복제한다. 복제된 Entity에는 `Disabled`와 비어 있는 `BattleOwner`가 붙는다. 이 작업은 시스템이
실제로 실행되는 프레임에 진행될 수 있으므로, Patch EntryPoint는 시스템의 공개 상태를 읽어
풀 생성까지 기다린다.

### 4. Pool warm-up과 게임 시작은 분리한다

현재 상태는 세 단계로 구분된다.

```text
loaded       Addressables와 SubScene이 필요한 데이터를 읽을 수 있음
ready        BattleSimulationSystem이 PoolSize만큼 Entity 풀을 만듦
started      InGame이 준비된 세션을 시작하고 전투 시간이 흐름
```

`ready`에서 `started`로 넘어가는 순간을 InGame의 `StartBattleSession()`으로 제한한 이유는
로딩 화면에서 Entity를 만들어도 실제 게임 시간은 흘러가면 안 되기 때문이다. 세션이 준비되기
전에는 `DeltaTime`을 0으로 두고, 시작 뒤에는 `Time.unscaledDeltaTime * Speed`를 사용한다.
따라서 게임 배속과 일시정지가 UI 프레임 시간 자체를 멈추지 않고 전투 시뮬레이션 시간만 바꾼다.

### 5. Shader Warm-up은 별도의 문제다

`ShaderVariantCollection`은 사용될 셰이더 키워드 조합을 모아 미리 준비하기 위한 자산이다.
현재 Patch는 Addressables로 컬렉션을 로드하고 `WarmUp()`을 호출한다. 이 API는 적어도 첫
사용 시 셰이더 컴파일로 생기는 멈춤을 줄이는 데 도움이 되지만, 그래픽 API에 따라 의미가 다르다.

Unity 문서에 따르면 DX11과 OpenGL에서는 `ShaderVariantCollection.WarmUp()`이 일반적인 방법으로
동작하지만, DX12·Vulkan·Metal에서는 정확한 vertex layout과 render state를 알 수 없어서 실제
필요한 GPU 표현을 다시 만들 때 지연이 남을 수 있다. 이 플랫폼에서는 실제 사용하는 Mesh,
Material, Pass, RenderTarget 조합을 오프스크린으로 렌더링하거나 Unity 6의 Graphics State
Collection/PSO tracing 흐름을 검토해야 한다.

그러므로 이 프로젝트에서 셰이더 Warm-up은 다음 두 층으로 이해한다.

1. **Variant warm-up**: SVC를 Addressables로 로드하고 `WarmUp()`을 호출한다.
2. **Render-state warm-up**: 대상 플랫폼에서 실제 렌더 상태를 포함해 오프스크린 렌더 또는
   Graphics State Collection으로 검증한다.

현재 구현은 첫 번째 층의 계약만 구현했고, 두 번째 층은 Unity 에디터와 빌드 타깃에서 측정해야 한다.

### 6. Font warm-up은 조건부다

TMP 폰트가 이미 Player 데이터나 정적 Atlas에 포함되어 있다면 매번 별도 Font Asset을 로드해
Warm-up할 필요가 없다. 동적 폰트 아틀라스나 런타임에 처음 생성되는 글리프가 있다면 필요한
폰트를 로딩 화면에서 읽고, 실제 표시할 문자열을 한 번 준비하는 별도 정책이 필요하다. 현재
Patch의 폰트 레이블을 비워 둔 것은 “폰트 Warm-up이 불필요하다”를 영원히 확정한 것이 아니라,
현재 프로젝트의 베이크된 폰트 경로를 중복 로드하지 않기 위한 기본값이다.

## 현재 구현 예시

Patch의 핵심 대기 구조는 다음과 같은 의미를 가진다.

```csharp
var ecsPrefabTask = LoadOptionalAssetsAsync<GameObject>("ECS.Warmup", "ECS prefab", ct);
var shaderTask = LoadOptionalAssetsAsync<ShaderVariantCollection>(
    "Graphics.Warmup", "shader variant", ct);

await UniTask.WhenAll(ecsPrefabTask, shaderTask);
WarmupShaderVariants(await shaderTask);
await WaitForEcsWarmupAsync(ct);
```

`WaitForEcsWarmupAsync`가 필요한 이유는 Addressables task가 끝나는 시점과
`BattleSimulationSystem`이 `EntityCommandBuffer`를 재생하고 풀을 완성하는 시점이 다를 수 있기
때문이다. 실제 코드에는 취소 토큰과 30초 timeout도 있어, SubScene이 누락되었을 때 로딩 화면이
영원히 멈추지 않도록 했다. 다만 timeout 뒤 계속 진행하는 정책은 개발 단계의 안전장치이므로,
출시 빌드에서는 필수 전투 리소스의 실패를 오류 화면으로 전환할지 결정해야 한다.

## 비교표

| 준비 대상 | 준비가 끝났다는 의미 | 현재 완료 신호 | 실패하면 생기는 문제 |
|---|---|---|---|
| Addressables | 에셋과 의존성을 읽을 수 있음 | `LoadByLabelAsync` 완료 | 프리팹/셰이더를 찾지 못함 |
| SubScene | baked Entity scene 스트리밍이 진행/완료됨 | 현재는 ECS system 상태를 함께 확인 | Entity query가 비어 있을 수 있음 |
| Entity pool | 활성화 가능한 적 Entity가 확보됨 | `IsWarmupComplete` | 첫 전투 프레임 Instantiate 지연 |
| Shader variant | 컬렉션의 variant 준비를 요청함 | `isWarmedUp`/호출 로그 | 첫 렌더 프레임 컴파일 hitch |
| GPU render state | 실제 플랫폼 상태까지 준비됨 | Profiler/Graphics State 측정 필요 | DX12/Vulkan/Metal에서 추가 PSO 지연 |

## 질문

- **Q. Pool warm-up이면 적 GameObject가 화면에 보이는가?**

  A. 아니다. ECS Entity는 만들어져 있지만 `Disabled` 상태라 쿼리와 렌더 경로에서 비활성으로
  취급된다. 실제 스폰 순간에 `Disabled`를 제거하고 위치·Owner·체력을 설정한다.

- **Q. 모든 프리팹을 앱 시작 시 풀링해야 하는가?**

  A. 아니다. 공통으로 반드시 쓰는 프리팹은 Patch에서 준비할 수 있지만, 특정 스테이지에서만
  쓰는 대형 적과 맵 데이터는 해당 스테이지 진입 직전에 준비하는 편이 메모리와 초기 로딩 시간에
  유리할 수 있다.

- **Q. ShaderVariantCollection을 WarmUp했는데도 끊길 수 있는가?**

  A. 그렇다. 특히 DX12, Vulkan, Metal에서는 SVC가 실제 vertex layout과 render state를
  완전히 표현하지 못할 수 있다. 반드시 대상 기기에서 첫 렌더 시점의 Profiler marker와 프레임
  시간을 확인해야 한다.

## 플로우차트

→ [`TD_Project-ECS-Warmup.flow.md`](./TD_Project-ECS-Warmup.flow.md)

## 실무

Warm-up은 “많이 하면 좋다”가 아니라 로딩 비용과 플레이 중 hitch를 교환하는 작업이다. 따라서
다음 지표를 기기별로 측정하는 것이 좋다.

- Patch 화면에서 첫 Title까지 걸린 시간
- SubScene 스트리밍 시작부터 `IsWarmupComplete`까지 걸린 시간
- 풀 생성 전후의 메모리 사용량과 Entity 수
- 첫 적 렌더 프레임의 CPU/GPU frame time
- Shader variant 수와 graphics state/PSO 생성 marker

측정 없이 모든 Shader를 Warm-up하거나 모든 적을 최대 풀 크기로 만들면 저사양 모바일에서
오히려 시작 시간이 길어지고 메모리 압박이 커질 수 있다. 풀 크기와 Warm-up 범위는 “첫 전투에서
반드시 필요한 것”부터 시작해 점진적으로 늘리는 편이 안전하다.

## 같이 보기

- [TD_Project — Unity ECS 코어 루프 아키텍처](./TD_Project.md)
- [URP 블룸 최적화](../Graphics/URP-Bloom-Optimization.md)
- [URP DOF 최적화](../Graphics/URP-DOF-Optimization.md)

## 참고자료

- [Unity Entities — Subscenes overview](https://docs.unity.cn/Packages/com.unity.entities@1.2/manual/conversion-subscenes.html)
- [Unity Addressables — Wait for asynchronous loads](https://docs.unity.cn/Packages/com.unity.addressables@3.0/manual/AddressableAssetsAsyncOperationHandle.html)
- [Unity — ShaderVariantCollection.WarmUp](https://docs.unity.cn/6000.7/Documentation/ScriptReference/ShaderVariantCollection.WarmUp.html)
- [Unity — Prewarm shaders](https://docs.unity.cn/Manual/shader-prewarm.html)
- [Unity — How Unity loads and uses shaders](https://docs.unity.cn/Manual/shader-loading.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-15 | 최초 작성. Addressables, SubScene, Entity pool, Shader/Font Warm-up을 분리해 정리 | Patch Warm-up 구현과 공식 Unity 문서 대조 |
