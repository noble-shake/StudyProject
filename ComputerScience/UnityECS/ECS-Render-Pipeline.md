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

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS Graphics와 URP 관계 정리 |
| 2026-09-17 | DOTS Instancing 개체별 Material Property 패턴 절 추가 | EnemyShader에서 프레임 인덱스·피격 틴트를 Material 복제 없이 개체별로 넘기는 실제 구현 |

