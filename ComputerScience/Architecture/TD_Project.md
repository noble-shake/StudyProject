# TD_Project — Unity ECS 코어 루프 아키텍처

---

- **카테고리**: 아키텍처, 게임 개발
- **상태**: 학습 중
- **기준 시점**: 2026-09-15, Unity 6 `6000.4.0b11` 목표
- **관련 레포지토리**: `TD_Project` (`noble-shake/TD_Project`)
- **엔진**: `Unity`
- **상위 문서**: -

---

> 이 문서는 `TD_Project`를 여러 기술 주제로 공부하기 위한 저장소 개요다. 현재 구현은
> `feature/check-core-loop`에서 진행 중인 ECS 코어 루프 기술 검증 단계이므로, 완성된 게임의
> 최종 설계가 아니라 실제 코드와 다음 확장 방향을 함께 기록한다.

## 출처

- `TD_Project`의 `DevelopPrompt/CurrentProject/_TD_Project/Study.md` — `STUDY-01`, `STUDY-02`, `STUDY-03`
- `DevelopPrompt/CurrentProject/_TD_Project/04_CURRENT_PROJECT.md` — ECS 코어 루프 기술 검증 기록
- `DevelopPrompt/CurrentProject/_TD_Project/CODE_MEMO.md` — `MEMO-ECS-01`~`MEMO-ECS-03`

## 정의

TD_Project는 모바일 우선 타워 디펜스 게임을 만들기 위한 Unity 프로젝트다. 일반적인 화면 흐름과
씬 오케스트레이션은 VContainer, UniTask, R3, Addressables를 이용하고, 전투 중 반복적으로
생성되고 이동하는 적의 런타임 데이터와 시뮬레이션은 Unity Entities 기반으로 검증하고 있다.

여기서 ECS 코어 루프는 “전투 Entity를 만들고, 일정에 따라 활성화하고, 상태를 갱신하고, 사용이
끝난 Entity를 다시 풀에 넣는” 최소한의 전투 실행 경로를 뜻한다. UI, 씬 전환, 리소스 로딩이
각자 따로 존재하는 것이 아니라, Patch 단계에서 전투 준비를 끝낸 뒤 InGame 단계에서 세션을
시작하는 하나의 흐름으로 연결된다.

## 요약

현재 구조의 핵심은 `BattleSession`을 ECS 상태의 기준으로 두고 `BattleSimulationSystem`이
Entity 풀을 관리하는 것이다. Patch 씬은 Addressables, SubScene 스트리밍, 선택적 셰이더 Warm-up을
진행하며, 시스템이 실제 풀 생성을 끝냈다는 신호까지 기다린 다음 다음 화면으로 넘어간다.

다만 이 단계는 단일 적 프리팹과 단순 스폰 설정을 검증하는 기술 프로토타입이다. 스테이지별
Blob 기반 일정, R3/ECS 브리지, Timeline/ECS 브리지는 방향만 정해졌고 아직 구현하지 않았다.

## 아키텍처

### 전체 흐름

게임플레이 준비는 대략 다음 순서로 이어진다.

1. Bootstrapper가 공용 매니저와 Patch 흐름을 시작한다.
2. Patch에서 로딩 UI를 표시하고 `ECS.Warmup` 레이블의 적 프리팹을 로드한다.
3. Patch 씬에 배치된 지속 SubScene 앵커가 테스트 SubScene을 자동 로드한다.
4. SubScene의 Authoring GameObject가 Baker를 거쳐 `BattleSession`과 적 프리팹 Entity가 된다.
5. `BattleSimulationSystem`이 적 Entity를 `PoolSize`만큼 복제하고 `Disabled` 상태로 보관한다.
6. Patch는 시스템의 `IsWarmupComplete`를 확인한 뒤 Title로 이동한다.
7. InGame에서 스테이지 Additive Scene이 준비되면 `TryStartSession()`으로 전투 시간을 시작한다.

이 흐름에서 “SubScene이 로드되었다”는 사실은 “게임플레이에 필요한 Entity와 풀이 준비되었다”는
뜻과 같지 않다. 그래서 현재 구현은 SubScene의 스트리밍 완료를 추측하지 않고, 시스템이 풀을
실제로 채운 뒤 세션을 준비 상태로 바꾸는 것을 별도의 완료 조건으로 둔다.

### 프로젝트 정책이 코드에 적용되는 방식

프로젝트의 규약 원본은 StudyProject가 아니라 DevelopPrompt다. DevelopPrompt의 Unity 문서와
`CurrentProject/_TD_Project`가 규칙과 프로젝트 맥락을 관리하고, 이 문서는 그 규칙을 실제
아키텍처에 적용해 이해하기 위한 교재다.

#### 일반 Unity 폴더 구조 안에 ECS를 배치한다

ECS라는 큰 폴더를 프로젝트 루트에 따로 만들지 않는다. 일반 코드와 같은 기준으로 도메인 코어에
배치한다.

```text
Assets/Dev/
├─ Cores/InGame/Battle/
│  ├─ Authoring/       # 인스펙터에서 편집하는 MonoBehaviour
│  ├─ Bakers/          # Authoring을 ECS 데이터로 변환
│  ├─ Components/      # IComponentData
│  ├─ Jobs/            # 병렬 처리 단위
│  ├─ Runtime/         # 런타임 수명 보조 코드
│  └─ Systems/Flow/    # 전투 흐름을 제어하는 System
└─ ScriptableObjects/InGame/Battle/
   └─ BattleSpawnConfigSO.cs
```

역할별 폴더를 나누는 이유는 “ECS라는 기술을 썼다”를 표시하기 위해서가 아니다. Authoring과
runtime 데이터, 변환 코드, 순수 계산, 흐름 제어를 서로 다른 책임으로 검색할 수 있게 하기
위해서다. 시스템이 커지면 System 파일을 CQRS처럼 명령과 조회로 더 나눌 수 있지만, 현재는
작은 코어 루프를 먼저 유지하고 책임이 실제로 갈라지는 시점에 분리한다.

#### ScriptableObject는 입력 데이터이고, 런타임 ECS 데이터가 아니다

`BattleSpawnConfigSO`는 디자이너가 스폰 범위, 간격, 총량, 풀 크기, 초기 배속, 난수 시드를
편집하기 위한 Unity 자산이다. Baker는 이를 읽어 `BattleSession`에 값과 Entity prefab 참조를
기록한다. 전투 프레임마다 ScriptableObject를 읽지 않으므로, 관리 객체와 Burst 친화적인
unmanaged 데이터를 분리할 수 있다.

이 구분은 이후 스테이지 일정이 커질 때도 유지한다. 편집 가능한 설정은 Authoring/SO에 남기고,
런타임에서 반복 조회할 불변 일정은 BlobAsset 또는 DynamicBuffer로 베이크한다. 관리 객체를
`IComponentData`에 넣어 편리하게 만드는 방식은 현재 프로젝트의 경계와 맞지 않는다.

#### ECS를 전투 상태의 단일 진실 공급원으로 둔다

`BattleSession`에는 일시정지, 배속, 경과 시간, 생성 수, 다음 생성 시점, 풀 생성 수가 들어간다.
UI가 이 값을 직접 소유하지 않는다. R3는 나중에 UI 명령과 읽기 모델을 연결하는 경계로 사용하고,
Timeline은 카메라·VFX·연출 신호를 보내는 경계로 사용하되 실제 전투 일정과 Entity 생성은 ECS가
담당하도록 한다.

#### 전투 Entity는 풀링을 기본으로 한다

적을 매 웨이브마다 새로 Instantiate하고 사망할 때 Destroy하는 방식은 이 프로젝트의 반복 전투
경로에 기본값으로 두지 않는다. 현재는 시작 전에 풀을 만들고, 활성화할 때 `Disabled`를 제거하며,
사용이 끝나면 다시 `Disabled`를 추가한다. 이렇게 해야 생성 비용과 구조적 변경을 전투 도중에
분산시킬 수 있고, 나중에 적 종류가 늘어나도 풀 전략을 명시적으로 확장할 수 있다.

## 현재 구현과 설계 예정 영역

| 영역 | 현재 구현 | 다음 확장 |
|---|---|---|
| 전투 상태 | 하나의 `BattleSession` unmanaged component | 여러 스테이지를 식별할 Descriptor/Registry |
| 스폰 데이터 | 단일 적 prefab, 간격, 총량, 위치 범위 | 적 종류·시점·위치를 담는 Blob/DynamicBuffer 일정 |
| SubScene | Patch에서 테스트 SubScene을 자동 로드 | 공통 풀과 스테이지 맵의 수명 분리 여부 검토 |
| 렌더 리소스 | 선택적 ShaderVariantCollection `WarmUp()` 계약 | 실제 SVC 수집·등록과 플랫폼별 PSO 검증 |
| UI 연결 | `TrySetPaused`, `TrySetSpeed` 같은 메인 스레드 API | R3 명령/Read Model 브리지 |
| 연출 연결 | 없음 | Timeline Signal/Track과 ECS 명령 브리지 |

현재 테스트 SubScene에는 세션과 적 프리팹이 함께 들어 있다. 이는 검증을 빠르게 하기 위한
구성이지, 모든 스테이지가 같은 SubScene을 공유해야 한다는 규칙은 아니다. SubScene을 나누는
기준은 시스템의 종류가 아니라 스트리밍, 메모리, 수명, 팀 작업 경계다.

## 비교표

| 관심사 | 현재 ECS 코어 루프 | 전통적인 GameObject 방식 |
|---|---|---|
| 상태 저장 | `IComponentData`의 구조화된 값 | MonoBehaviour 필드와 객체 참조 |
| 생성 | 사전 복제한 Entity 풀 재사용 | Instantiate/Destroy 또는 별도 GameObject 풀 |
| 데이터 입력 | Authoring/SO를 Baker가 런타임 데이터로 변환 | 런타임 객체가 SO를 직접 참조하기 쉬움 |
| 준비 완료 | 시스템이 `IsWarmupComplete`를 명시 | 각 객체의 Awake/Start 완료를 간접 추측하기 쉬움 |
| UI 연결 | 브리지가 ECS 명령/읽기 모델을 전달 | View가 객체를 직접 호출하기 쉬움 |

## 질문

- **Q. 시스템은 매 프레임 실행되는가?**

  A. 기본적으로 시스템은 자신이 속한 그룹의 업데이트 때 실행된다. 현재
  `BattleSimulationSystem`도 `BattleSession`이 존재하는 동안 매 프레임 업데이트하지만,
  세션이 시작되기 전에는 시간을 진행하지 않고, 일시정지 중에는 `DeltaTime`을 0으로 만든다.
  `RequireForUpdate<BattleSession>()`로 세션이 없을 때는 시스템 업데이트 자체를 막는다.

- **Q. SubScene을 로드하면 곧바로 Entity를 사용할 수 있는가?**

  A. 아니다. 닫힌 SubScene은 빌드에서 baked entity scene으로 스트리밍되고, Entity가 사용
  가능해지는 시점은 비동기 작업의 영향을 받는다. 이 프로젝트는 시스템의 준비 완료 신호를
  별도로 기다린다.

- **Q. 스포너마다 별도 System이 필요한가?**

  A. 책임이 실제로 다를 때 나눈다. 현재는 하나의 `BattleSimulationSystem`이 최소 코어 루프를
  담당한다. 캐릭터, 탄막, 보스가 서로 다른 일정·풀·명령 모델을 갖게 되면 Spawn Command,
  Pool, Flow 같은 단위로 분리할 수 있지만, 이름만 ECS답게 늘리는 것은 목표가 아니다.

## 예시 코드

다음은 현재 프로젝트가 선택한 “풀링된 Entity를 일정에 따라 활성화한다”는 핵심 형태를 단순화한
예시다. 실제 코드는 `BattleSimulationSystem.cs`에서 `EntityCommandBuffer`와
`BattleSession`을 함께 사용한다.

```csharp
if (session.IsReady == false)
{
    PrewarmPool(ref session, commands);
    session.IsReady = session.PoolCreatedCount >= session.PoolSize;
    return;
}

if (session.IsStarted && session.IsPaused == false)
{
    session.DeltaTime = Time.unscaledDeltaTime * session.Speed;
    session.ElapsedSeconds += session.DeltaTime;
    SpawnFromPool(ref session, sessionEntity, commands);
}
```

여기서 중요한 점은 `IsReady`와 `IsStarted`가 분리되어 있다는 것이다. 준비 완료는 리소스와
Entity 풀이 존재한다는 뜻이고, 시작은 게임 규칙상 시간이 흐르기 시작했다는 뜻이다.

## 플로우차트

Warm-up의 시간 순서는 별도 문서에 그렸다.

→ [`TD_Project-ECS-Warmup.flow.md`](./TD_Project-ECS-Warmup.flow.md)

## 실무

이 구조는 전투 중 많은 수의 반복 객체를 처리하고, 첫 플레이 프레임의 생성 지연을 로딩 화면으로
옮기고 싶을 때 유용하다. 다만 모든 Entity를 앱 시작 때 무조건 만들면 메모리와 초기 로딩 시간이
커질 수 있다. 공통 프리팹은 Patch에서 준비하고, 스테이지별 대규모 데이터는 InGame 진입 직전에
준비하는 식으로 비용을 나누는 것이 현실적이다.

풀 크기는 예상 최대 동시 활성 수와 재사용 정책을 기준으로 정해야 한다. 현재 검증 코드는
`PoolSize >= TotalCount`를 요구하지만, 실제 게임에서는 “전체 생성 수”보다 “동시에 살아 있을 수
있는 수”가 풀 크기의 더 좋은 기준이 될 수 있다. 이 값은 플레이 로그와 프로파일러로 측정하며
결정해야 한다.

## 같이 보기

- [TD_Project ECS Warm-up](./TD_Project-ECS-Warmup.md)
- [Unity URP 블룸 최적화](../Graphics/URP-Bloom-Optimization.md)
- [Unity URP DOF 최적화](../Graphics/URP-DOF-Optimization.md)

## 참고자료

- [Unity Entities — Baking overview](https://docs.unity.cn/Packages/com.unity.entities@1.1/manual/baking-overview.html)
- [Unity Entities — Subscenes overview](https://docs.unity.cn/Packages/com.unity.entities@1.2/manual/conversion-subscenes.html)
- [Unity Entities — Baking phases](https://docs.unity.cn/Packages/com.unity.entities@1.0/manual/baking-phases.html)
- `DevelopPrompt/Unity/03_ARCHITECTURE.md`, `DevelopPrompt/Unity/ECS/CONVENTIONS.md`
- `TD_Project/Assets/Dev/Cores/InGame/Battle/`

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-15 | 최초 작성. 프로젝트 정책, ECS 코어 루프, 현재 구현과 미구현 경계를 정리 | `feature/check-core-loop`의 ECS/Patch Warm-up 검증 |
