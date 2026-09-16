# Unity ECS와 SRP 렌더 파이프라인의 관계

---

- **카테고리**: Unity ECS, 그래픽스, URP
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Entities Graphics 1.x 개념 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `-`

---

## 출처

- `TD_Project` ECS Graphics prefab 검증
- [Unity Entities Graphics overview](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.4/manual/overview.html)

## 정의

Entities Graphics는 URP나 HDRP를 대체하는 새 렌더 파이프라인이 아니다. ECS Entity의 transform·mesh·material 관련 Component를 모아 batch로 만들고, 그 결과를 Unity의 기존 SRP 렌더링 구조에 전달하는 **브리지**다. 렌더 패스, 조명, 포스트 프로세싱, 쉐이더 작성의 중심은 여전히 URP 또는 HDRP다.

## 요약

ECS는 “무엇을 얼마나 많이 시뮬레이션할 것인가”에 강하고, SRP는 “그 결과를 어떤 순서와 품질로 그릴 것인가”에 책임이 있다. Entities Graphics는 두 층 사이에서 renderable Entity를 수집·culling·batching한다. 그래서 RendererFeature나 URP 커스텀 패스를 만들 때 ECS를 별도 파이프라인으로 생각하면 안 된다. 기존 URP pass가 같은 카메라와 조명 조건에서 ECS batch도 그리도록 연결된다.

## 상세

### 베이킹에서 런타임 렌더 데이터로

SubScene 안의 MeshRenderer가 달린 GameObject 또는 prefab authoring은 베이킹 과정에서 렌더링에 필요한 Entity Component로 변환된다. 런타임에는 `LocalToWorld`, 렌더 mesh 정보, bounds, material property Component 같은 데이터를 Entities Graphics가 처리한다. 복잡한 적·탄환처럼 반복 생성할 대상은 **미리 baked된 Entity prefab을 Instantiate**하는 편이 런타임에 렌더 Component를 하나씩 조립하는 것보다 안정적이다.

Entities Graphics는 처리 대상 Entity를 batch로 묶어 Unity 렌더링 아키텍처에 전달한다. 같은 mesh·material을 많이 공유할수록 batching 기회가 늘어난다. 하지만 ECS Entity라고 해서 draw call이 자동으로 하나가 되는 것은 아니다. material, mesh, light mode, shadow 설정, material property 차이와 culling 결과가 batch를 나눈다.

### URP와의 경계

URP는 카메라별 렌더 순서, depth·opaque·transparent pass, 조명, shadow, post processing을 결정한다. Entities Graphics는 이 URP의 앞뒤를 마음대로 바꾸지 않는다. 따라서 다음 구분이 실용적이다.

| 관심사 | 주 책임 |
|---|---|
| 대량 적 이동·상태 | ECS Simulation System |
| mesh와 material을 가진 Entity 준비 | Baker와 Entities Graphics |
| culling·batch 데이터 수집 | Entities Graphics |
| 조명·렌더 패스·포스트 프로세싱 | URP/HDRP |
| 커스텀 fullscreen 효과 | URP RendererFeature 또는 Volume |

ECS Entity의 위치는 Simulation System이 `LocalTransform`을 바꾸고, transform 관련 System이 렌더에 필요한 월드 행렬 데이터를 반영하는 흐름으로 전달된다. Presentation 시점 이후에는 culling Job이 같은 상태를 전제로 할 수 있으므로, PresentationGroup에서 구조 변경을 무분별하게 하면 안 된다.

### 라이팅 Scene과 SubScene

일반 Additive Scene에 카메라, Light, Volume, 반사 probe 같은 GameObject 기반 라이팅 구성을 두고, SubScene의 ECS Entity를 렌더할 수 있다. Scene이 제공하는 조명 환경과 Entity의 mesh·normal·material 반응은 같은 SRP 프레임 안에서 만난다. 따라서 “맵 라이팅은 Additive Scene, 대량 전투 단위는 SubScene” 같은 분리는 자연스럽다.

단, Scene을 바꿀 때 bake된 lightmap·reflection·volume 전환이 실제 타깃 플랫폼에서 자연스러운지 별도로 검증해야 한다. ECS가 존재한다고 라이팅 데이터의 streaming 또는 shader variant 문제가 사라지지는 않는다.

### DOTS Instancing으로 개체별 Material Property 넘기기

Entities Graphics가 여러 Entity를 하나의 batch로 그릴 때, Material 자체는 하나만 쓰면서도
개체마다 다른 값(예: 스프라이트 애니메이션 프레임, 피격 틴트 세기)을 넘겨야 하는 경우가
흔하다. `Graphics.DrawMeshInstanced`에 쓰던 `MaterialPropertyBlock`과 달리, Entities
Graphics는 **DOTS Instancing**이라는 별도 경로로 이걸 처리한다 — Material을 개체 수만큼
복제하지 않고도 개체별 값을 GPU 버퍼로 넘긴다.

URP의 손으로 짠(hand-written HLSL, ShaderGraph 아님) 셰이더가 이 경로를 타려면 세 가지가
필요하다.

1. **패스에 인스턴싱 프라그마를 건다.**
   ```hlsl
   #pragma multi_compile_instancing
   #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"
   ```
   `DOTS.hlsl`이 내부적으로 `#pragma multi_compile _ DOTS_INSTANCING_ON`과 타깃 레벨을
   같이 설정해 준다.

2. **개체별로 달라져야 하는 프로퍼티만 `UNITY_DOTS_INSTANCING_START` 블록으로 선언한다.**
   나머지(공유되는 텍스처, 타일링 값 등)는 평소처럼 `CBUFFER_START(UnityPerMaterial)`에
   둔다 — 전부를 인스턴싱 프로퍼티로 만들 필요는 없다.
   ```hlsl
   #ifdef UNITY_DOTS_INSTANCING_ENABLED
   UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
       UNITY_DOTS_INSTANCED_PROP(float, _FrameIndex)
       UNITY_DOTS_INSTANCED_PROP(float, _HitFlash)
   UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)
   ```

3. **매크로 오버라이드로 기존 이름을 그대로 쓸 수 있게 한다.** `UNITY_SETUP_INSTANCE_ID`가
   호출될 때 자동으로 `UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES()`를 실행하도록 정의해두면,
   버텍스/프래그먼트 함수 코드는 `_FrameIndex`, `_HitFlash`를 원래 이름 그대로 쓰면서도
   실제로는 인스턴스별 값을 읽게 된다(URP 자체 셰이더들이 `_BaseColor` 등에 쓰는 것과
   같은 패턴).
   ```hlsl
   static float unity_DOTS_Sampled_FrameIndex;
   void SetupDOTSEnemyMaterialPropertyCaches()
   {
       unity_DOTS_Sampled_FrameIndex = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _FrameIndex);
   }
   #undef UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES
   #define UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES() SetupDOTSEnemyMaterialPropertyCaches()
   #define _FrameIndex unity_DOTS_Sampled_FrameIndex
   #endif
   ```

이 패턴을 안 쓰고 개체별로 다른 시각 효과를 주려던 흔한 대안이 "개체마다 Material 인스턴스
복제"인데, 이건 정확히 batching을 깨뜨려서 Entities Graphics를 쓰는 의미를 없앤다 — draw
call이 다시 개체 수만큼 늘어난다.

### 다른 프레임워크의 접근 — Latios Framework의 LifeFX

같은 문제("ECS 개체별 데이터를 어떻게 GPU 렌더링 쪽에 전달하나")를 다르게 푸는 프레임워크가
있는지 비교해보면 우리 선택의 위치를 더 잘 이해할 수 있다. Latios Framework(Dreaming381의
개인 Unity DOTS 프레임워크, `github.com/Dreaming381/Latios-Framework`)는 Kinemation(애니메이션/
메쉬 최적화), Calligraphics(월드스페이스 텍스트), LifeFX(대규모 VFX) 등의 모듈로 구성되는데,
**전용 2D 스프라이트 렌더링 모듈은 없다.**

가장 가까운 모듈은 LifeFX다. 공식 설명은 다음과 같다.

> "provides VFX solutions at ECS scales using an intelligent graphics buffer management
> pipeline" — "an out-of-the-box solution for sending ECS event payloads to VFX Graph via
> graphics buffers, as well as synchronizing entity transforms with the GPU" — "a single
> VFX Graph instance can support thousands of entities."

즉 LifeFX는 이 문서 위쪽에서 설명한 "DOTS Instancing으로 개체별 Material Property 넘기기"와
**목적은 같지만 방법이 다르다.**

| | 이 문서의 DOTS Instancing 방식 | Latios LifeFX |
|---|---|---|
| 개체별 데이터 전달 경로 | 커스텀 HLSL 셰이더에 `UNITY_DOTS_INSTANCING_START` 매크로 직접 작성 | ECS 이벤트를 GraphicsBuffer로 Unity **VFX Graph**에 전달 |
| 렌더링 주체 | Material + 손으로 짠 URP 셰이더 | VFX Graph 에셋(비주얼 스크립팅) |
| 텍스처 시트/프레임 애니메이션 | 셰이더 코드에서 직접 UV 계산 | VFX Graph 내장 Flipbook 노드 |
| 커스텀 라이팅 모델 제어 | 셰이더 코드를 직접 고치면 됨(예: 스펙큘러/프레넬 빼기) | VFX Graph의 출력 셰이더 그래프 쪽에서 별도로 맞춰야 함 |
| 확장 규모 | Material 하나 기준, 배치는 Entities Graphics가 처리 | "VFX Graph 인스턴스 하나로 수천 개체" — 파티클 스케일 전제 |

두 방식 다 "Material을 개체 수만큼 복제하지 않는다"는 목표는 같지만, DOTS Instancing 직접
구현은 셰이더 코드 전체를 손으로 통제할 수 있는 대신 보일러플레이트가 필요하고, LifeFX는
VFX Graph의 기성 기능(플립북, 파티클 스케일 최적화)을 공짜로 얻는 대신 커스텀 라이팅
로직은 VFX Graph의 셰이더 그래프 안에서 다시 구성해야 한다. 셀 스타일처럼 라이팅 모델
자체를 세밀하게 통제해야 하는 경우, 코드로 완전히 열려 있는 DOTS Instancing 직접 구현
쪽이 오히려 더 다루기 쉬울 수 있다.

### 다른 프레임워크의 접근 — NSprites (전용 2D 스프라이트 ECS 프레임워크)

Latios가 2D 전용 모듈이 없는 것과 달리, `Antoshidza/NSprites`(+ `NSprites-Foundation`)는 처음부터
Unity Entities와 함께 쓰는 **전용 2D 스프라이트 렌더링 프레임워크**다. 이 문서의 "DOTS
Instancing으로 개체별 Material Property 넘기기"와 목적은 완전히 같지만, 경로가 근본적으로
다르다 — **Entities Graphics/BatchRendererGroup을 아예 쓰지 않는다.**

> "sync registered entity components with ComputeBuffers to send data to GPU and then
> renders entities with Graphics.DrawMeshInstancedProcedural"

즉 개체 컴포넌트 값을 직접 `ComputeBuffer`로 올리고, 셰이더에서는 `StructuredBuffer`를
인스턴스 ID로 인덱싱해서 읽는다.

```hlsl
StructuredBuffer<int> _propertyPointers;
StructuredBuffer<float4> _color;

Varyings UnlitVertex(Attributes attributes, uint instanceID : SV_InstanceID)
{
    int propPointer = _propertyPointers[instanceID];
    float4 color = _color[propPointer];
}
```

`_propertyPointers`로 한 번 더 간접 참조하는 이유는(인스턴스 ID를 버퍼 인덱스에 직접 매핑하지
않는 것) 엔티티가 파괴/재사용될 때 버퍼 전체를 재정렬하지 않고 포인터만 갱신하기 위해서로
보인다 — 우리가 `Disabled` 태그로 풀링하며 Entity Index 자체는 안정적으로 유지하는 것과 다른
방식으로 같은 "재사용 시 데이터 정합성" 문제를 푼다.

Foundation 확장 패키지는 이 기반 위에 2D 게임에 특화된 시스템을 얹는다.

- **애니메이션**: "Shifts UV values to simulate sprite animation" — 이 문서의 `GetFrameUV`와
  목적이 같은 플립북 UV 시프트.
- **정렬(Sorting)**: "Calculate SortingValue depending on 2D position to use in shader" —
  Z-버퍼 깊이 대신 2D 위치로 그리기 순서를 계산한다.
- **컬링**: 2D 위치 기준 카메라 컬링(기본 비활성 — 성능 트레이드오프상 옵트인).

| | 이 문서의 DOTS Instancing 방식 | NSprites |
|---|---|---|
| 렌더 경로 | Entities Graphics가 자동 배치 | `Graphics.DrawMeshInstancedProcedural` 직접 호출 |
| 개체별 데이터 전달 | DOTS Instancing 매크로 | `ComputeBuffer`/`StructuredBuffer` 직접 관리 + 포인터 간접 참조 |
| 그리기 순서 | 표준 Z-버퍼 깊이 정렬(Opaque) | 2D 위치 기반 수동 정렬 |
| 필요한 인프라 | Entities Graphics가 배치·컬링 담당 | 등록·용량 관리·정렬·컬링을 직접 구현 |

**TD_Project에 실제로 적용해보면**: NSprites가 2D 위치 정렬을 따로 만든 이유는 보통 "투명
스프라이트가 겹칠 때 Z-버퍼만으론 그리기 순서가 안 맞는" 순수 2D(카메라와 같은 평면에 깔린
스프라이트 다수) 게임의 문제다. TD_Project는 `MEMO-ACTOR-09`처럼 실제 3D 좌표계를 쓰고
`EnemyShader`의 Quad도 현재 Opaque(Z-write 켜짐)라서, 표준 Z-버퍼 정렬이 이미 올바르게
동작한다 — 지금 시점엔 이 문제 자체가 없다. 다만 그린스크린 알파 블렌딩을 붙여서 Enemy Quad가
반투명(Transparent 큐)으로 바뀌면, 겹치는 스프라이트의 그리기 순서가 카메라 거리 기준
근사 정렬로만 처리돼 부정확해질 수 있다 — 그 시점에 이 NSprites 정렬 패턴을 다시 참고할 만하다.

#### 성능 관점 — "다른 선택"이 아니라 "그 시절엔 없었던 선택지"

NSprites 저장소는 **2022-03**에 만들어졌다(최근까지 유지보수는 되고 있음, 마지막 커밋
2025-06). 이 시점은 Unity Entities가 1.0 정식 출시 전, Hybrid Renderer/초기 Entities
Graphics가 아직 미숙하던 때다. `ComputeBuffer` + `Graphics.DrawMeshInstancedProcedural`를
직접 관리하는 선택은 "Entities Graphics보다 낫다고 판단해서"가 아니라, **당시엔 대량
인스턴싱을 할 다른 실용적인 방법이 없었기 때문**일 가능성이 크다.

- 옛 `Graphics.DrawMeshInstanced`(상수 버퍼 배열 기반)는 인스턴스당 1023개 한도가 있었다.
  `DrawMeshInstancedProcedural` + `ComputeBuffer`는 이 한도를 피하는 사실상 유일한
  우회로였다.
- 당시엔 지금의 **GPU Resident Drawer**(Unity 6/URP가 BatchRendererGroup 인스턴스 데이터를
  GPU에 상주시키고 컬링·배치까지 GPU에서 처리해주는 기능)가 존재하지 않았다. NSprites
  Foundation 문서가 자체 컬링을 "성능 문제로 기본 비활성"이라 밝힌 것도, 손으로 짠 컬링이
  지금 엔진 차원의 GPU 드리븐 컬링만큼 효율적이지 못했다는 정황이다.

BatchRendererGroup(Entities Graphics의 기반)도 `DrawMeshInstancedProcedural`과 마찬가지로
1023개 한도가 없다 — 같은 문제를 이미 해결한 상태고, 거기에 GPU Resident Drawer가 NSprites가
2022년에 손으로 짰던 최적화를 엔진 차원에서 대신 해준다. NSprites는 그 초기 아키텍처 결정에
계속 묶여 있어서, 프레임워크를 갈아엎지 않는 한 이런 엔진 발전을 자동으로 못 받는다.

**결론**: 지금(Unity 6000.4.0b11, Entities Graphics 6.4.0) 기준으로는 Entities Graphics +
DOTS Instancing 쪽이 성능적으로 더 유리할 가능성이 높다. 단, 이건 각 접근이 문서화한
아키텍처적 능력에 근거한 추론이지 두 방식을 동일 조건에서 실측 프로파일링한 결과는 아니다.
TD_Project의 목표 규모(500~1,000마리, `Docs/TODO.md`)에서는 어느 쪽이든 드로우콜 제출
자체가 병목일 가능성은 낮고, 시뮬레이션(Job/Burst) 쪽이 먼저 병목일 확률이 더 크다 — 실제
차이가 궁금해지면 프로파일러로 직접 재는 것이 유일하게 확실한 답이다.

## 비교표

| 오해 | 실제 |
|---|---|
| Entities Graphics가 URP를 대체한다 | 아니다. ECS 데이터를 기존 SRP에 전달한다. |
| Entity면 자동으로 단일 draw call이다 | 아니다. batch는 mesh·material·렌더 상태에 따라 나뉜다. |
| ECS는 렌더 전용 기술이다 | 아니다. 주 역할은 데이터 중심 시뮬레이션이며 렌더는 선택적 연동이다. |
| Additive Scene 라이팅은 ECS Entity에 무관하다 | 아니다. 같은 SRP 카메라에서 Entity material도 그 라이팅 환경의 영향을 받는다. |

## 질문

- **Q. ECS는 SRP의 어느 단계인가?**
  A. ECS 전체는 SRP의 한 단계가 아니다. Simulation은 PlayerLoop의 게임 로직 단계에 있고, Entities Graphics가 그 결과를 SRP 렌더링 입력으로 연결한다.

- **Q. RendererFeature에서 ECS Entity만 따로 처리할 수 있나?**
  A. 가능 여부는 URP/Entities Graphics 버전과 pass 목적에 따라 다르다. 보통은 layer, render queue, material, renderer list 같은 URP의 기존 필터링 도구로 접근한다. ECS 내부 Component를 RendererFeature가 직접 순회하는 설계는 렌더와 simulation 경계를 흐릴 수 있다.

## 플로우차트

[`ECS-Render-Pipeline.flow.md`](./ECS-Render-Pipeline.flow.md)

## 실무

- 다수 prefab은 SubScene에서 baked한 Entity prefab으로 준비하고, 런타임에 그래픽 Component를 수동 조립하지 않는다.
- “ECS라서 빠를 것” 대신 Profiler에서 batch 수, CPU culling, GPU frame time을 실제로 측정한다.
- custom shader는 Entities Graphics·URP target 플랫폼에서 필요한 instancing과 material property 경로를 확인한다.
- Shader warm-up은 ECS pool warm-up과 별개다. Entity를 만들었다고 GPU render state가 반드시 준비된 것은 아니다.

## 같이 보기

- [Entity, Component, System](./Entity-Component-System.md)
- [SubScene과 씬 스트리밍](./SubScene-Streaming.md)
- [Spawner, Pool, Warm-up](./Spawner-Pooling-Warmup.md)
- [TD_Project ECS Warm-up](../Architecture/TD_Project-ECS-Warmup.md)
- [노멀맵 인코딩과 디퓨즈/스펙큘러/프레넬/림 라이팅](../Graphics/Normal-Mapping-and-Lighting-Models.md)
  — 이 배치 경로로 그려지는 EnemyShader의 라이팅 계산 자체

## 참고자료

- [Unity Entities Graphics](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.2/manual/index.html)
- [Unity Entities Graphics overview](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.4/manual/overview.html)
- [Unity Entities Graphics requirements](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.2/manual/requirements-and-compatibility.html)
- [Latios Framework](https://github.com/Dreaming381/Latios-Framework) — LifeFX 모듈의
  ECS→VFX Graph GraphicsBuffer 브리지 비교 출처
- [NSprites](https://github.com/Antoshidza/NSprites) / [NSprites-Foundation](https://github.com/Antoshidza/NSprites-Foundation)
  — ComputeBuffer 직접 관리 + 2D 위치 정렬 비교 출처

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS Graphics와 URP 관계 정리 |
| 2026-09-17 | DOTS Instancing 개체별 Material Property 패턴 절 추가 | EnemyShader에서 프레임 인덱스·피격 틴트를 Material 복제 없이 개체별로 넘기는 실제 구현 |
| 2026-09-17 | Latios Framework LifeFX와의 비교 절 추가 | 사용자가 제시한 다른 ECS 프레임워크(`STUDY-05`)의 2D/개체별 GPU 데이터 전달 방식 검토 |
| 2026-09-17 | NSprites(전용 2D 스프라이트 ECS 프레임워크)와의 비교 절 추가 | 사용자가 제시한 프레임워크(`STUDY-06`) 검토 — ComputeBuffer 직접 관리와 2D 위치 정렬 방식 확인 |
| 2026-09-17 | NSprites 비교에 성능 관점 절 추가 | NSprites의 2022년 아키텍처 선택이 "다른 판단"이 아니라 "당시 Entities Graphics 미성숙으로 인한 제약"이었음을 확인, GPU Resident Drawer와 비교 |

