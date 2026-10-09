# DevelopPrompt 규약 참조 애널리틱스 — 이벤트가 화면에 닿기까지

> `DevelopPrompt-Analytics.md`의 별첨 플로우차트. 작성 규칙은
> `DevelopPrompt/Unity/VISUALIZE_RULE/04_MERMAID_STYLE.md`를 따른다.
> 기준 시점: 2026-10-09

```mermaid
flowchart TD
    %% ── 수집 ────────────────────────────
    AG["에이전트 · Read / Grep 호출"]
    TR["트랜스크립트 JSONL · 계속 덧붙여 씀"]
    HK["PostToolUse hook · 선택, 미설치"]

    %% ── 서버 프로세스 ───────────────────
    subgraph SRV["serve.py · 127.0.0.1 전용"]
        EV["events.py · 새로 붙은 줄만 읽기"]
        AN["analyze.py · 빈도, 전이, 절별, 마지막 질문"]
        CA["1초 캐시 · 새 이벤트 없으면 분석 생략"]
    end

    %% ── 브라우저 ───────────────────────
    subgraph WEB["브라우저"]
        PL["3초 폴링 · /api/report"]
        TP["전체 화면 Topology · 마지막 질문 강조, 반복 재생"]
        OV["하단 오버레이 · 통계, 로그, 목록, 재생"]
    end

    %% ── 관계 ────────────────────────────
    AG --> TR
    AG -.->|"설치 시"| HK
    TR --> EV
    HK -.-> EV
    EV --> AN --> CA
    CA --> PL
    PL --> TP
    PL --> OV

    %% ── 스타일 ──────────────────────────
    classDef hi fill:#1f2f3a,stroke:#3498db,color:#d5e8f5
    classDef good fill:#1f3a2a,stroke:#27ae60,color:#d5f5e3
    class EV hi
    class TP good
```

**읽는 법**: 위에서 아래로 데이터가 흐른다. 에이전트가 도구를 호출하면 Claude Code가 그 사실을
트랜스크립트에 덧붙인다(실선). hook 경로(점선)는 설치했을 때만 생기는 두 번째 입구다. 서버 안에서는
`events.py`가 파일마다 읽은 위치를 기억해 새 줄만 이벤트로 바꾸고, 분석 결과는 1초 동안 재사용된다.
브라우저는 3초마다 결과를 받아 Topology와 오버레이를 함께 갱신한다.

**핵심 한 줄**: 실시간의 비결은 빠른 전송이 아니라 "새로 붙은 줄만 읽는다"는 증분 읽기다.
