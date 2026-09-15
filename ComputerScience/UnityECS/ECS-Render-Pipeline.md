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

## 참고자료

- [Unity Entities Graphics](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.2/manual/index.html)
- [Unity Entities Graphics overview](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.4/manual/overview.html)
- [Unity Entities Graphics requirements](https://docs.unity.cn/Packages/com.unity.entities.graphics@1.2/manual/requirements-and-compatibility.html)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 근거 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS Graphics와 URP 관계 정리 |

