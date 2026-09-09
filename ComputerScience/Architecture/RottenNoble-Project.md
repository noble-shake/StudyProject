# RottenNoble-Project — 저장소 개요

---

- **카테고리**: 웹 개발, 아키텍처
- **상태**: 완료
- **기준 시점**: 2026-09-09
- **관련 레포지토리**: `RottenNoble-Project`

---

> 이 문서는 개별 기술 하나를 다루는 다른 문서들과 달리, **`RottenNoble-Project` 저장소 전체를
> 조망하는 색인 겸 아키텍처 요약**이다. 각 기술의 자세한 설명은 아래 표에서 링크된 개별 문서를
> 본다. 코드를 순서대로 훑어간 세션 기록 자체는
> [`RottenNobleProject-Architecture.md`](./RottenNobleProject-Architecture.md)에 남아있다.
>
> **(2026-09-09 갱신) 전환 완료 + 프로덕션 배포됨 — 그러나 Git 상태와 어긋나 있다.** 2026-09-08에
> 시작된 PHP → Java Spring Boot 전환(원래 PR #3, `server/` 모듈)은 그 PR이 머지 없이 close된 뒤,
> 다른 세션이 브랜치 `rewrite/spring-boot-vite`(`develop`에서 분기, 아직 PR 없음)에서
> `backend-spring/`라는 새 모듈로 다시 짜서 **실제로 프로덕션에 배포하고 검증까지 마쳤다** —
> 지금 `rotten-noble.com`이 서빙하는 백엔드는 더 이상 PHP가 아니라 Spring Boot다. 프런트 빌드
> 도구도 CRA→Vite로 같이 전환·배포됨. 다만 이 모든 변경이 저장소의 `develop`/`main` 브랜치엔 아직
> 머지되지 않아, **실제 배포 상태가 git 히스토리보다 앞서 있는** 상태다. 아래 "기술 스택"/
> "특이할 점"은 이 최신 상태를 반영해 갱신했다 — 전환 배경과 실측으로 드러난 세부 내용은
> [Spring Boot](../WebDevelopment/Spring-Boot.md)에 정리했다.

## 출처

`RottenNobleProject` — 개별 주제 문서 12개를 다 쓴 뒤, 전체 그림을 한 곳에서 볼 수 있도록
작성한 개요 문서.

## 정의

RottenNoble은 가비아 도메인과 Synology NAS로 직접 운영하는 개인 포트폴리오 블로그(게시글 +
방명록)다. React 프런트엔드와 Java Spring Boot 백엔드가 완전히 독립된 두 프로세스로 실행되고,
HTTP/JSON으로 통신한다(`POLICY/MULTI_ENGINE.md`의 Peer 패턴). 원래는 프레임워크 없는 PHP
백엔드였으나 2026-09-09 기준 Spring Boot로 완전히 교체돼 프로덕션에 배포된 상태다 — PHP는
학습 기록과 롤백 대비용으로만 코드가 남아있다.

## 요약

이 저장소는 "프레임워크가 해주던 일을 손으로 직접 짜본다"는 학습 목표와 "이미 가진 NAS를
활용한다"는 비용 제약, 이 두 축이 대부분의 기술 선택을 설명한다. 그 결과 백엔드·프런트엔드
양쪽 다 "파일 하나 = 역할 하나"라는 대칭적으로 얇은 구조를 갖게 됐고, 인증만큼은 기존
인프라(Redis)와의 일관성을 위해 실무 표준(JWT)이 아닌 opaque 세션 토큰을 선택했다.

## 아키텍처

### 레이어 구조

```
프런트엔드(React, CRA)              백엔드(PHP, 프레임워크 없음)
─────────────────────              ────────────────────────────
pages/*.jsx  (라우트 1개 = 폴더 1개)   *.php (엔드포인트 1개 = 파일 1개)
     │                                    │
api/*.js  (리소스 1개 = 파일 1개) ──JSON──▶ response.php (CORS + 봉투)
     │                                    │
auth.js (localStorage 토큰)         auth.php (require_admin 가드)
                                          │
                                     db.php (MariaDB) / redis_client.php (Redis)
```

→ 레이어 구조를 그림으로 본 상세 버전은
[`RottenNoble-Project.flow.md`](./RottenNoble-Project.flow.md).

**(2026-09-09) 위 다이어그램은 PHP 시절 기준이다.** 지금 프로덕션의 백엔드 계층은
`backend-spring/`(Spring Boot, 컨트롤러/서비스/리포지토리 계층 구조)로 바뀌었지만, "프런트가
`api/*.js`로 JSON 호출 → 백엔드가 봉투에 담아 응답"이라는 통신 계약 자체는 그대로다. 새 계층
구조는 [Spring Boot](../WebDevelopment/Spring-Boot.md) 참고 — 그림은 아직 갱신하지 않았다(PHP
버전도 학습 자료로서 여전히 유효해 남겨둠).

### 데이터가 실제로 흐르는 경로

1. 브라우저가 `pages/*.jsx`를 렌더링 → `api/*.js`가 `fetch`로 백엔드 호출
2. PHP 엔드포인트가 `response.php`(CORS)·`auth.php`(보호된 엔드포인트만)를 거쳐 요청 처리
3. `db.php`(MariaDB, 글/방명록 같은 영구 데이터) 또는 `redis_client.php`(Redis, 세션처럼
   휘발성 데이터)로 실제 데이터 접근
4. `response.php`의 `send_json`/`send_error`로 `{status, data|message}` 봉투에 담아 응답
5. `api/*.js`의 공통 `request()`가 봉투를 까서 페이지 컴포넌트에 순수 데이터만 전달

## 기술 스택

| 계층 | 기술 | 상세 문서 |
|---|---|---|
| 백엔드 언어 | **Java Spring Boot 4.1.1(Java 21), `backend-spring/`** — 2026-09-09 프로덕션 배포 완료. PHP는 롤백 대비용으로만 코드 보존 | [PHP](../WebDevelopment/PHP.md), [Spring Boot](../WebDevelopment/Spring-Boot.md) |
| 관계형 DB | MariaDB 10 (Spring Data JPA + Flyway `baseline-on-migrate`, 기존 PHP 시절 스키마 그대로 채택) | [MariaDB](../Database/MariaDB.md) |
| 세션 저장소 | Redis (PHP 시절엔 RESP 직접 구현, Spring은 `spring-boot-starter-data-redis`) | [Redis](../Infrastructure/Redis.md) |
| 인증 방식 | Opaque 토큰 + Redis 세션 (JWT 아님) — 전환 후에도 그대로 유지 | [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) |
| 비밀번호 저장 | bcrypt (`spring-security-crypto`의 `BCryptPasswordEncoder`, 기존 PHP 해시와 호환) | [비밀번호 해싱](../Security/Password-Hashing.md) |
| API 스타일 | REST(`/api/**`, 경로 변수 방식으로 변경) + `{status, data\|message}` 봉투 유지 | [REST API 설계](../WebDevelopment/REST-API-Design.md) |
| 프런트엔드 | React 19 | [React](../WebDevelopment/React.md) |
| 라우팅 | react-router-dom, `HashRouter` | [React Router](../WebDevelopment/React-Router.md) |
| 빌드 도구 | **CRA → Vite 전환 완료(2026-09-09)**, 의존성 1188→64개 | [CRA → Vite](../WebDevelopment/CRA-vs-Vite.md) |
| 토큰 저장 | 브라우저 `localStorage` | [Token Storage](../Security/Token-Storage.md) |
| CORS | **와일드카드**(`*`) — 2026-09-08에 준비된 허용목록 패치는 머지 안 됨, 새 Spring 백엔드가 다시 와일드카드를 명시적으로 선택 | [CORS](../Network/CORS.md) |
| 배포 인프라 | Synology NAS — 프런트/구 PHP는 Web Station, 새 Spring 백엔드는 Docker 컨테이너 + `api.rotten-noble.com` 서브도메인(리버스 프록시가 경로 라우팅 미지원) | [HTTPS & Mixed Content](../Network/HTTPS-and-Mixed-Content.md), [자체 호스팅 vs 클라우드](../Infrastructure/Self-Hosting-vs-Cloud.md) |
| 요청 제한 | Redis 기반 IP별 rate limiting — Spring `@RateLimit`+인터셉터로 이식, 프로덕션 검증됨 | [Rate Limiting](../Security/Rate-Limiting.md) |
| 개인정보 저장 | **암호화 없음(회귀)** — PHP 시절 AES-256-GCM이 새 Spring 백엔드엔 이식 안 됨 | [저장 데이터 암호화](../Security/Encryption-at-Rest.md) |

## 특이할 점

이 저장소를 훑으며 "보통의 튜토리얼 프로젝트와 다르다"고 느낀 지점들을 모았다.

1. **세 언어가 프로토콜 수준에서 인프라를 공유한다.** PHP(`redis_client.php`)가 라이브러리 없이
   RESP 프로토콜을 직접 구현한 이유는, Node(`RottenNoble-HttpServer`)와 C++
   (`RottenNoble-TCPServer`)가 같은 Redis 인스턴스를 완전히 동일한 커맨드 패턴으로 다뤄야 하기
   때문이다 — 이 저장소 하나만 봐서는 이유가 안 보이고, 형제 저장소들과의 관계를 알아야 이해되는
   설계다.
2. **실무 표준(JWT)을 알면서도 의도적으로 다른 선택을 했다.** `MEMO-WEB-04`를 보면 JWT를 몰라서
   Redis 세션을 쓴 게 아니라, "이 규모에서는 즉시 무효화가 확장성보다 중요하다"는 판단 아래
   의도적으로 비주류를 택했다. 문서에 그 비교와 근거가 명시적으로 남아있다는 게 특이하다.
3. **문서화된 보안 결정과 실제 코드가 갈라졌다가, 실제 공격 시도를 계기로 다시 합쳐졌다가, 스택
   재작성으로 또 갈라진 사례가 있다.** `MEMO-WEB-02`가 "인증 엔드포인트엔 CORS 와일드카드를
   복사하지 말라"고 스스로 경고해뒀는데, 처음 구현은 그 경고를 지키지 못한 채 배포됐다 — 2026-09-08
   실제 스캔/프로빙을 겪은 뒤에야 명시적 origin 허용목록·rate limiting·방명록 암호화가 PHP
   패치로 준비됐다. 하지만 백엔드가 곧바로 Spring Boot로 재작성되면서 그 PHP 패치는 머지될 기회
   없이 close됐고, 새 스택엔 **rate limiting만 이식되고 CORS 허용목록과 암호화는 빠졌다**
   ([CORS](../Network/CORS.md), [Rate Limiting](../Security/Rate-Limiting.md),
   [저장 데이터 암호화](../Security/Encryption-at-Rest.md)의 "2026-09-09 갱신" 절 참고).
   "알려진 갭이 실제로 익스플로잇되기 전까지는 우선순위에서 밀린다"는 패턴에 더해, "스택을
   갈아엎는 재작성은 이전에 고쳐둔 보안 항목을 명시적 체크리스트 없이도 조용히 되돌릴 수 있다"는
   패턴까지 이 저장소 하나에서 두 번 다 관찰된다.
4. **인프라 제약이 기술 선택을 여러 단계로 역산시켰다.** "이미 NAS가 있다" → "NAS가 MariaDB를
   기본 지원한다" → "로컬도 같은 Apache+PHP 조합(XAMPP)으로 맞춘다"로 이어지는 연쇄, 그리고
   "Web Station GUI로 rewrite 설정을 못 만진다" → "HashRouter로 우회한다"는 연쇄가 둘 다 같은
   NAS 선택 하나에서 갈라져 나왔다.
5. **"프레임워크가 없다"는 선택이 백엔드/프런트 양쪽에서 대칭적으로 나타난다(PHP 시절 기준).**
   백엔드는 파일 하나가 엔드포인트 하나, 프런트는 페이지 폴더 하나가 라우트 하나 — 서로 다른
   언어인데 구조적 철학이 같다. 두 계층을 서로 다른 세션에서 배웠는데도 나중에 보니 같은
   패턴이었다는 게 이 저장소를 순서대로 훑는 재미이기도 하다.
6. **실제 배포 상태가 이 저장소의 git 히스토리보다 앞서 있다.** 2026-09-09 기준, 프로덕션에
   떠 있는 Spring Boot+Vite 코드는 브랜치 `rewrite/spring-boot-vite`에만 존재하고
   `develop`/`main`엔 아직 머지되지 않았으며 그 브랜치용 PR조차 없다 — 반면 그 이전에 이 스택
   전환을 시도했던 PR #2·#3(같은 목표, 다른 구현)는 머지 없이 close됐다. 저장소를 git 로그만
   보고 파악하면 "아직 PHP를 쓰고 있다"고 착각하기 쉽다 — 개인 프로젝트에서 "일단 빨리 배포해
   두고 PR/머지는 나중에"라는 흐름이 git 상태를 실제 운영 상태의 신뢰할 만한 스냅샷이 아니게
   만들 수 있다는 걸 보여주는 사례다.

## 같이 보기 (문서 전체 지도)

- [RottenNobleProject 아키텍처 이해하기](./RottenNobleProject-Architecture.md) — 세션별 코드 학습 기록(1~3회차)
- [PHP](../WebDevelopment/PHP.md) · [MariaDB](../Database/MariaDB.md) · [Redis](../Infrastructure/Redis.md) — 백엔드 언어/저장소
- [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) · [비밀번호 해싱](../Security/Password-Hashing.md) ·
  [CORS](../Network/CORS.md) · [Token Storage](../Security/Token-Storage.md) ·
  [Rate Limiting](../Security/Rate-Limiting.md) · [저장 데이터 암호화](../Security/Encryption-at-Rest.md) — 인증/보안
- [REST API 설계](../WebDevelopment/REST-API-Design.md) — 백엔드-프런트 통신 규약
- [React](../WebDevelopment/React.md) · [React Router](../WebDevelopment/React-Router.md) · [CRA → Vite](../WebDevelopment/CRA-vs-Vite.md) — 프런트엔드
- [Spring Boot](../WebDevelopment/Spring-Boot.md) — 완료·배포된 백엔드 전환
- [자체 호스팅 vs 클라우드](../Infrastructure/Self-Hosting-vs-Cloud.md) · [HTTPS & Mixed Content](../Network/HTTPS-and-Mixed-Content.md) — 인프라

## 참고자료

- `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md` — 제품 정의, 엔드포인트 표
- `DevelopPrompt/CurrentProject/_RottenNobleProject/CODE_MEMO.md` — `MEMO-WEB-01`~`11` 전체
  (`MEMO-WEB-11`이 이 문서의 2026-09-09 갱신 근거)
- `RottenNoble-Project`(`develop` 브랜치는 아직 PHP/CRA 기준 — 실제 배포는 `rewrite/spring-boot-vite`)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 개별 주제 문서 12개를 다 쓴 뒤 전체 그림을 한 문서로 종합 |
| 2026-09-08 | CORS/rate limiting/암호화 반영 | 실제 스캔/프로빙 대응으로 추가된 방어 심층화를 기술 스택 표·특이할 점에 갱신 |
| 2026-09-08 | PHP → Spring Boot 전환 시작 안내 추가 | 시니어 리뷰 이후 백엔드 전면 교체 결정 — `server/` 모듈 신설(PR #3), 세부 내용은 `Spring-Boot.md`로 분리 |
| 2026-09-09 | 전환 완료·프로덕션 배포로 갱신(기술 스택 표, 특이할 점, 아키텍처 다이어그램 주석) — git/실배포 상태 불일치, CORS/암호화 회귀 기록 | PR #2·#3는 머지 없이 close, 다른 세션이 `rewrite/spring-boot-vite`로 재구현·배포 완료 |
