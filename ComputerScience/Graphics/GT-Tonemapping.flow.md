# GT 톤매퍼 — 입력값이 세 구간 중 어디로 가는가

> `GT-Tonemapping.md`의 별첨 플로우차트. 작성 규칙은
> `DevelopPrompt/Unity/VISUALIZE_RULE/04_MERMAID_STYLE.md`를 따른다.
> 기준 시점: 2026-09-09

```mermaid
flowchart TD
    X["입력 HDR 값 x"]
    LT{"x 가 m 보다 작은가? - 어두운 영역"}
    GT{"x 가 S0(선형 구간 끝) 보다 큰가? - 밝은 영역"}

    TOE["토(toe) - m * (x/m)^c + b - 거듭제곱 압축"]:::hi
    LIN["선형(linear) - m + a*(x-m) - 진짜 직선, 왜곡 없음"]:::good
    SHO["숄더(shoulder) - P - (P-S1)*exp(...) - 지수 롤오프, P에 수렴"]:::hi

    OUT["최종 출력 색"]

    X --> LT
    LT -->|"예"| TOE --> OUT
    LT -->|"아니오"| GT
    GT -->|"예"| SHO --> OUT
    GT -->|"아니오"| LIN --> OUT

    classDef good fill:#1f3a2a,stroke:#27ae60,color:#d5f5e3
    classDef hi   fill:#1f2f3a,stroke:#3498db,color:#d5e8f5
```

**읽는 법**: 두 개의 판정(`LT`, `GT`)이 입력값을 토/선형/숄더 세 구간으로 나눈다. 실제 셰이더
코드에서는 이 분기를 `if`가 아니라 `smoothstep`/`step` 기반 가중치 블렌딩으로 처리해서, 구간
경계에서 값이 뚝 끊기지 않고 매끄럽게 이어진다 — 이 그림은 "어느 구간의 수식이 지배적으로
작용하는가"를 이해하기 위한 단순화다.

**핵심**: 파라미터 `m`(선형 구간 시작)과 `l`(선형 구간 길이)이 이 세 구간의 경계 자체를
움직인다 — 즉 GT 톤매퍼를 튜닝한다는 건 이 플로우차트의 분기 조건 자체를 바꾸는 일과 같다.
ACES/Reinhard처럼 곡선 모양이 고정된 톤매퍼에는 애초에 이런 분기 자체가 없다.
