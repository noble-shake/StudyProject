# System 생명주기: System은 언제 실제로 일하는가

기준: 2026-09-15, Entities 1.x 개념 기준.

```mermaid
flowchart TD
    %% ── 생명주기 ──────────────────────
    CRT["System 생성"]:::hi
    OCREATE["OnCreate"]
    READY{"실행 조건 충족"}
    START["OnStartRunning"]
    UPDATE["OnUpdate"]:::good
    STOP["OnStopRunning"]
    DESTROY["OnDestroy"]

    %% ── 관계 ──────────────────────────
    CRT --> OCREATE
    OCREATE --> READY
    READY -->|"예"| START
    START --> UPDATE
    UPDATE --> READY
    READY -->|"아니오"| STOP
    STOP --> READY
    STOP --> DESTROY

    %% ── 스타일 ────────────────────────
    classDef good fill:#1f3a2a,stroke:#27ae60,color:#d5f5e3
    classDef hi fill:#1f2f3a,stroke:#3498db,color:#d5e8f5
```

**읽는 법**: 화살표는 System의 실행 상태 전이를 뜻한다. `실행 조건 충족`은 `RequireForUpdate`, query 매칭, System enabled 상태 등을 포함한다.

**핵심**: `OnCreate`가 호출되었다는 사실은 SubScene Entity나 pool이 준비되었다는 뜻이 아니다. 실제 게임 로직은 조건을 만족한 `OnUpdate`부터 시작한다.

