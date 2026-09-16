# 개체별 GPU 데이터 전달 — Entities Graphics vs Latios LifeFX vs NSprites

---

- **카테고리**: Unity ECS, 그래픽스
- **상태**: 완료
- **기준 시점**: 2026-09-17, Entities Graphics 6.4.0 / Unity 6000.4.0b11 기준
- **관련 레포지토리**: `TD_Project`
- **엔진**: `Unity`
- **상위 문서**: `ComputerScience/UnityECS/ECS-Render-Pipeline.md`(그 문서의 "다른 프레임워크의
  접근" 절들에서 별도 문서로 분리됨)

---

## 출처

- `TD_Project` `STUDY-05`, `STUDY-06` — `DevelopPrompt/CurrentProject/_TD_Project/Study.md`

## 정의

Unity ECS/DOTS로 같은 mesh·material을 쓰는 개체를 대량으로(수백~수천) 그릴 때, 개체마다
Material을 복제하지 않으면서도 **개체별로 다른 작은 값**(색상 틴트, 애니메이션 프레임,
피격 여부 등)을 GPU/셰이더에 전달해야 하는 공통 문제가 있다. Unity 생태계 안에도 이 문제를
푸는 방식이 하나가 아니다 — 이 문서는 실제로 검토한 세 가지를 비교한다.

1. **Entities Graphics + DOTS Instancing** — `TD_Project`의 `EnemyShader`가 쓰는 방식.
2. **Latios Framework의 `LifeFX`** — ECS 이벤트를 Unity VFX Graph로 넘기는 방식.
3. **NSprites** — Entities Graphics를 거치지 않고 `ComputeBuffer`를 직접 관리하는 방식.

## 요약

셋 다 "Material을 개체 수만큼 복제하지 않는다"는 목표는 같지만 방법이 다르다. Entities
Graphics + DOTS Instancing은 Unity의 표준 ECS 렌더 경로를 그대로 타면서 필요한 프로퍼티만
오버라이드하는 가장 정석적인 방법이고, Latios LifeFX는 렌더링 자체를 VFX Graph에 위임하는
브리지이며, NSprites는 Entities Graphics 성숙 이전 시기의 제약 때문에 GPU 버퍼를 직접
관리하는 방식으로 만들어졌다. 현재(Unity 6, Entities Graphics 6.4.0) 시점에서는 Entities
Graphics 경로가 성능·유지보수 양쪽에서 가장 유리하다고 판단해 `EnemyShader`는 이 방식을
유지한다.

## 상세

### 공통 문제

Unity의 오래된 `Graphics.DrawMeshInstanced`(상수 버퍼 배열 기반 인스턴싱)는 호출 하나당
인스턴스 1023개 한도가 있다. 그보다 많은 개체를 한 draw call로 그리려면 다른 경로가
필요한데, 세 프레임워크가 각자 다른 시점에 다른 답을 골랐다.

### 1. Entities Graphics + DOTS Instancing

Unity ECS의 표준 렌더 브리지인 Entities Graphics는 내부적으로 **BatchRendererGroup**을
쓴다. Simulation System이 쓴 Component 데이터(Transform, 렌더 관련 Component)를 Entities
Graphics가 batch로 묶어 URP/HDRP에 넘긴다(자세한 배치·culling 구조는 상위 문서
[ECS-Render-Pipeline.md](./ECS-Render-Pipeline.md) 참고).

여기서 개체마다 달라야 하는 셰이더 프로퍼티(예: 애니메이션 프레임, 피격 틴트)는 셰이더 코드
안에 `UNITY_DOTS_INSTANCING_START` 매크로 블록으로 선언한다. 나머지 공유 프로퍼티(텍스처,
타일링 값 등)는 평소처럼 `CBUFFER_START(UnityPerMaterial)`에 둔다. `UNITY_SETUP_INSTANCE_ID`
호출 시 자동으로 개체별 값을 캐싱하도록 매크로를 오버라이드해서, 셰이더 나머지 코드는
`_FrameIndex`처럼 원래 이름을 그대로 쓴다(실제 코드는 아래 [예시 코드] 참고).

Unity 6부터는 여기에 **GPU Resident Drawer**가 더해진다 — BatchRendererGroup 인스턴스
데이터를 GPU에 상주시키고, 컬링·배치 갱신까지 GPU 드리븐으로 처리해서 CPU 부담을 줄인다.
이건 엔진이 제공하는 기능이라 우리가 따로 구현할 게 없다.

### 2. Latios Framework — LifeFX

Latios Framework(`github.com/Dreaming381/Latios-Framework`)는 전용 2D 스프라이트 모듈이
없다. 가장 가까운 모듈은 `LifeFX`인데, 이건 셰이더에 개체별 프로퍼티를 직접 넣는 방식이
아니라 **ECS 이벤트를 GraphicsBuffer로 Unity VFX Graph에 전달**하는 브리지다. 공식 설명:

> "provides VFX solutions at ECS scales using an intelligent graphics buffer management
> pipeline" — "an out-of-the-box solution for sending ECS event payloads to VFX Graph via
> graphics buffers... a single VFX Graph instance can support thousands of entities."

즉 프레임 인덱스나 피격 틴트 같은 값을 ECS 쪽에서 이벤트로 발행하면, VFX Graph가 그 값을
받아서 **자기 내장 기능**(Flipbook 애니메이션 노드, 파티클 색상 등)으로 렌더링한다. 셰이더
코드를 손으로 쓰는 대신 VFX Graph를 비주얼 스크립팅으로 구성하는 셈이라, 이 접근에는 직접
비교할 만한 HLSL 코드 스니펫이 없다 — 렌더링 로직 자체가 코드 밖(VFX Graph 에셋)에 있다.

### 3. NSprites — ComputeBuffer 직접 관리

NSprites(`github.com/Antoshidza/NSprites`, 2022-03 생성)는 Entities Graphics를 아예 쓰지
않는다. 대신 개체 Component 값을 직접 `ComputeBuffer`로 GPU에 올리고,
`Graphics.DrawMeshInstancedProcedural`로 그린다. 공식 설명:

> "sync registered entity components with ComputeBuffers to send data to GPU and then
> renders entities with Graphics.DrawMeshInstancedProcedural"

셰이더에서는 `StructuredBuffer`를 인스턴스 ID로 직접 인덱싱해서 값을 읽는다(코드는
[예시 코드] 참고). 인스턴스 ID를 버퍼 인덱스에 바로 매핑하지 않고 `_propertyPointers`로 한
번 더 간접 참조하는데, 이건 개체가 파괴/재사용될 때 버퍼 전체를 재정렬하지 않고 포인터만
갱신하기 위한 것으로 보인다.

확장 패키지 `NSprites-Foundation`이 2D 게임에 필요한 상위 기능을 얹는다 — UV 시프트로
플립북 애니메이션을 만들고, **2D 위치 기반으로 그리기 순서를 계산하는 정렬 시스템**,
2D 위치 기반 컬링(기본 비활성)을 제공한다.

**왜 이런 아키텍처였나 (성능/시대 관점)**: NSprites는 2022-03 생성으로, Unity Entities
1.0 정식 출시 전, Entities Graphics가 아직 미성숙하던 시기다. `ComputeBuffer` 직접 관리는
"Entities Graphics보다 나은 설계"라기보다, 당시 `DrawMeshInstanced`의 1023개 한도를 피할
실용적 방법이 그것뿐이었을 가능성이 크다. Foundation이 자체 컬링을 "성능 문제로 기본
비활성"이라 밝힌 것도, 손으로 짠 컬링이 지금 엔진 차원의 GPU 드리븐 컬링만큼 효율적이지
못했다는 정황이다. 지금(Unity 6, Entities Graphics 6.4.0) 기준으로는 BatchRendererGroup도
같은 1023개 한도가 없고, GPU Resident Drawer가 NSprites가 손으로 짰던 최적화(컬링·배치)를
엔진 차원에서 대신 해준다 — NSprites는 초기 아키텍처 결정에 계속 묶여 있어 이런 엔진 발전을
자동으로 받지 못한다.

### TD_Project에 실제로 적용해보면

- TD_Project는 `04_CURRENT_PROJECT.md`/`MEMO-ACTOR-09`처럼 실제 3D 좌표계를 쓰고,
  `EnemyShader`의 Quad도 현재 Opaque(Z-write 켜짐)다. NSprites가 2D 위치 정렬을 만든 이유인
  "투명 스프라이트가 겹칠 때 Z-버퍼만으론 순서가 안 맞는" 문제 자체가 지금은 없다.
- 다만 그린스크린 알파 블렌딩을 붙여서 Enemy Quad가 Transparent 큐로 바뀌면, 겹치는
  스프라이트의 그리기 순서가 카메라 거리 기준 근사 정렬로만 처리돼 부정확해질 수 있다 — 그
  시점에 NSprites의 2D 위치 정렬 패턴을 다시 참고할 만하다.
- Latios LifeFX 방식(VFX Graph 위임)으로 옮겨갈 계획은 없다. 셀 스타일 커스텀 라이팅(스펙큘러/
  프레넬 제외, [노멀맵/라이팅 문서](./../Graphics/Normal-Mapping-and-Lighting-Models.md) 참고)을
  세밀하게 통제하려면, 렌더링 로직이 코드 밖(VFX Graph 에셋)에 있는 것보다 지금처럼 커스텀
  셰이더를 직접 쓰는 편이 다루기 쉽다.

## 비교표

| | Entities Graphics + DOTS Instancing (우리 방식) | Latios LifeFX | NSprites |
|---|---|---|---|
| 렌더 경로 | BatchRendererGroup(Entities Graphics 내부) | Unity VFX Graph | `Graphics.DrawMeshInstancedProcedural` 직접 호출 |
| 개체별 데이터 전달 | 셰이더 내 DOTS Instancing 매크로 | ECS 이벤트 → GraphicsBuffer → VFX Graph | `ComputeBuffer`/`StructuredBuffer` 직접 관리 + 포인터 간접 참조 |
| 렌더링 로직 위치 | 코드(HLSL 셰이더) | VFX Graph 에셋(비주얼 스크립팅) | 코드(HLSL 셰이더 + C# 등록/버퍼 관리 시스템) |
| UV/프레임 애니메이션 | 셰이더에서 직접 계산 | VFX Graph 내장 Flipbook 노드 | Foundation의 UV 시프트 시스템 |
| 그리기 순서 정렬 | 표준 Z-버퍼(Opaque) | VFX Graph 내장 정렬 옵션 | 2D 위치 기반 수동 정렬(Foundation) |
| 컬링·배치 최적화 | GPU Resident Drawer(엔진 제공, Unity 6+) | VFX Graph 내장 | 직접 구현(기본 비활성) |
| 1023개 인스턴스 한도 | 없음(BatchRendererGroup) | 해당 없음(VFX Graph 자체 파이프라인) | 없음(`DrawMeshInstancedProcedural`로 우회) |
| 만들어진/성숙해진 시기 | Unity 공식, Entities 1.0 이후 지속 발전 | Latios 개인 프레임워크, VFX Graph 의존 | 2022-03, Entities 1.0 이전 아키텍처 |
| 커스텀 라이팅 통제 | 셰이더 코드로 완전 통제 | VFX Graph 셰이더 그래프에서 재구성 필요 | 셰이더 코드로 완전 통제 |

## 질문

- **Q. 왜 NSprites나 Latios를 바로 채택하지 않았나?**
  A. Latios LifeFX는 렌더링을 VFX Graph에 위임하는 구조라, 셀 스타일 커스텀 라이팅(스펙큘러/
  프레넬 제외)처럼 세밀한 통제가 필요한 우리 요구와 안 맞는다. NSprites는 Entities Graphics
  자체를 버리는 트레이드오프가 큰데, 그 아키텍처가 필요했던 이유(1023개 한도, 컬링 최적화
  부재)가 지금 Entities Graphics/GPU Resident Drawer 조합에서는 이미 해결돼 있어서 이점이
  없다.

- **Q. 성능은 어느 쪽이 더 좋은가?**
  A. 문서화된 아키텍처 능력에 근거하면 지금(Unity 6, Entities Graphics 6.4.0) 시점엔 우리
  방식이 더 유리할 가능성이 높다 — NSprites가 손으로 짰던 최적화를 GPU Resident Drawer가
  엔진 차원에서 대신 해주기 때문이다. 다만 이건 추론이지 세 방식을 동일 조건에서 실측
  프로파일링한 결과는 아니다. TD_Project의 목표 규모(500~1,000마리)에서는 어느 쪽이든
  드로우콜 제출 자체가 병목일 가능성은 낮고, 시뮬레이션(Job/Burst) 쪽이 먼저 병목일 확률이
  더 크다.

- **Q. NSprites의 2D 위치 정렬을 우리도 언젠가 필요로 하게 될까?**
  A. 지금은 아니다. Enemy Quad가 Opaque라 표준 Z-버퍼 정렬로 충분하다. 그린스크린 알파
  블렌딩을 붙여 Transparent 큐로 바뀌는 시점에 다시 검토 대상이 된다.

## 예시 코드

**Entities Graphics + DOTS Instancing** — `TD_Project`의 `EnemyShader.shader`에서 개체별로
달라야 하는 값(`_FrameIndex`, `_HitFlash`)만 오버라이드하는 부분.

```hlsl
#ifdef UNITY_DOTS_INSTANCING_ENABLED
UNITY_DOTS_INSTANCING_START(MaterialPropertyMetadata)
    UNITY_DOTS_INSTANCED_PROP(float, _FrameIndex)
    UNITY_DOTS_INSTANCED_PROP(float, _HitFlash)
UNITY_DOTS_INSTANCING_END(MaterialPropertyMetadata)

static float unity_DOTS_Sampled_FrameIndex;
static float unity_DOTS_Sampled_HitFlash;

void SetupDOTSEnemyMaterialPropertyCaches()
{
    unity_DOTS_Sampled_FrameIndex = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _FrameIndex);
    unity_DOTS_Sampled_HitFlash   = UNITY_ACCESS_DOTS_INSTANCED_PROP_WITH_DEFAULT(float, _HitFlash);
}

#undef UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES
#define UNITY_SETUP_DOTS_MATERIAL_PROPERTY_CACHES() SetupDOTSEnemyMaterialPropertyCaches()

#define _FrameIndex unity_DOTS_Sampled_FrameIndex
#define _HitFlash   unity_DOTS_Sampled_HitFlash
#endif
```

**NSprites** — 셰이더에서 `StructuredBuffer`를 인스턴스 ID로 직접 인덱싱하는 부분(README
발췌).

```hlsl
StructuredBuffer<int> _propertyPointers;
StructuredBuffer<float4> _color;

Varyings UnlitVertex(Attributes attributes, uint instanceID : SV_InstanceID)
{
    int propPointer = _propertyPointers[instanceID];
    float4 color = _color[propPointer];
}
```

**Latios LifeFX**: 렌더링 로직이 VFX Graph 에셋(비주얼 스크립팅) 안에 있어서, 위 두 예시와
나란히 비교할 HLSL/C# 코드 스니펫이 없다. ECS 쪽에서는 이벤트 페이로드를 발행하는 코드만
작성하고, 그 값을 실제로 어떻게 그릴지는 VFX Graph 에디터에서 노드로 구성한다.

## 플로우차트

[`ECS-Instancing-Frameworks.flow.md`](./ECS-Instancing-Frameworks.flow.md)

## 실무

- Unity 공식 경로(Entities Graphics)를 탈 수 있으면 그게 기본 선택지다 — 엔진 업데이트가
  성능 개선을 공짜로 가져다준다(GPU Resident Drawer가 그 예).
- VFX Graph 브리지(Latios LifeFX 방식)는 파티클처럼 "그리는 방식 자체가 표준적인" 대상에
  강하다. 우리처럼 커스텀 라이팅 모델을 촘촘히 통제해야 하는 캐릭터 스프라이트에는 안 맞다.
- 커스텀 GPU 버퍼 직접 관리(NSprites 방식)는 지금도 유효한 선택지일 수 있다 — 단, "표준
  경로가 아직 못 푸는 구체적인 문제"(예: 특정 엔진 버전이 지원 안 하는 기능, 매우 특수한
  정렬/컬링 요구)가 있을 때만 그 복잡도를 감수할 가치가 있다. "예전에 필요했던 이유"와
  "지금도 필요한 이유"를 구분해서 판단해야 한다.

## 같이 보기

- [ECS와 Unity 렌더 파이프라인](./ECS-Render-Pipeline.md) — Entities Graphics와 URP의
  일반적인 관계, batch/culling 구조.
- [노멀맵 인코딩과 디퓨즈/스펙큘러/프레넬/림 라이팅](../Graphics/Normal-Mapping-and-Lighting-Models.md)
  — 우리가 커스텀 셰이더를 직접 쓰기로 한 이유인 셀 스타일 라이팅 통제.

## 참고자료

- [Latios Framework](https://github.com/Dreaming381/Latios-Framework)
- [NSprites](https://github.com/Antoshidza/NSprites)
- [NSprites-Foundation](https://github.com/Antoshidza/NSprites-Foundation)
- [Unity — GPU Resident Drawer (URP)](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/gpu-resident-drawer.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-17 | 최초 작성 — `ECS-Render-Pipeline.md`의 Latios/NSprites 비교 절을 이 문서로 분리·정리, 예시 코드와 플로우차트 추가 | 사용자가 두 프레임워크 비교 내용을 예시 코드·구조 포함해 정식 항목으로 정리해달라고 요청 |
