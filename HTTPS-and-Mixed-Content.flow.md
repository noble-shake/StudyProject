# HTTPS 인증서 발급 — 포트 우회와 ACME 챌린지가 언제 어긋났나

> `HTTPS-and-Mixed-Content.md`의 별첨 플로우차트. 작성 규칙은
> `DevelopPrompt/Unity/VISUALIZE_RULE/04_MERMAID_STYLE.md`를 따른다.
> 기준 시점: 2026-09-08

```mermaid
flowchart TD
    SETUP["가상 호스트 생성 시도"] --> CONFLICT{"80/443이 기본 서버와 충돌"}
    CONFLICT -->|"우회"| REROUTE["내부 8081/8443 + 포트포워딩 80→8081"]:::hi
    REROUTE --> ACME["Let's Encrypt 발급 요청"]
    ACME --> CHALLENGE["외부 80으로 소유권 확인 요청"]
    CHALLENGE --> WRONG["내부 8081로 전달 - DSM 80 리스너 못 만남"]:::bad
    WRONG --> FAIL["발급 실패"]:::bad

    FAIL --> REVERT["포트포워딩 80→80(내부)으로 임시 복귀"]:::good
    REVERT --> ACME2["재발급 요청"]
    ACME2 --> OK["ACME 챌린지 정상 응답"]:::good
    OK --> RESTORE["포트포워딩 80→8081로 복귀"]:::good
    RESTORE --> DONE["HTTPS 서비스 시작"]

    classDef bad  fill:#3a1f1f,stroke:#c0392b,color:#f5d5d5
    classDef good fill:#1f3a2a,stroke:#27ae60,color:#d5f5e3
    classDef hi   fill:#1f2f3a,stroke:#3498db,color:#d5e8f5
```

**읽는 법**: 파란 노드(`REROUTE`)가 "정상 운영을 위해 필요했던 우회"이고, 빨간 노드들은 그 우회
때문에 인증서 발급이 실패한 지점, 초록 노드들은 그걸 되돌려서 문제를 해결한 지점이다.

**핵심**: 포트 우회(`8081/8443`)는 평상시 트래픽에는 문제가 없지만, Let's Encrypt의 소유권 확인은
반드시 외부 80번이 NAS의 실제 80번으로 가야만 성립한다 — "평소엔 필요했던 설정"과 "인증서 발급
순간에만 방해가 되는 설정"이 같은 값이었다는 게 이 문제의 핵심이다.
