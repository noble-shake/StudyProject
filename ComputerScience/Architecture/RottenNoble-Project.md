# RottenNoble-Project — 저장소 개요

---

- **카테고리**: 웹 개발, 아키텍처
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`

---

> 이 문서는 개별 기술 하나를 다루는 다른 문서들과 달리, **`RottenNoble-Project` 저장소 전체를
> 조망하는 색인 겸 아키텍처 요약**이다. 각 기술의 자세한 설명은 아래 표에서 링크된 개별 문서를
> 본다. 코드를 순서대로 훑어간 세션 기록 자체는
> [`RottenNobleProject-Architecture.md`](./RottenNobleProject-Architecture.md)에 남아있다.

## 출처

`RottenNobleProject` — 개별 주제 문서 12개를 다 쓴 뒤, 전체 그림을 한 곳에서 볼 수 있도록
작성한 개요 문서.

## 정의

RottenNoble은 가비아 도메인과 Synology NAS로 직접 운영하는 개인 포트폴리오 블로그(게시글 +
방명록)다. React 프런트엔드와 프레임워크 없는 PHP 백엔드가 완전히 독립된 두 프로세스로 실행되고,
HTTP/JSON으로 통신한다(`POLICY/MULTI_ENGINE.md`의 Peer 패턴).

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
| 백엔드 언어 | PHP 8.x, 프레임워크 없음 | [PHP](../WebDevelopment/PHP.md) |
| 관계형 DB | MariaDB 10 (`mysqli`) | [MariaDB](../Database/MariaDB.md) |
| 세션 저장소 | Redis (RESP 프로토콜 직접 구현) | [Redis](../Infrastructure/Redis.md) |
| 인증 방식 | Opaque 토큰 + Redis 세션 (JWT 아님) | [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) |
| 비밀번호 저장 | bcrypt (`password_hash`/`password_verify`) | [비밀번호 해싱](../Security/Password-Hashing.md) |
| API 스타일 | REST + `{status, data\|message}` 봉투 | [REST API 설계](../WebDevelopment/REST-API-Design.md) |
| 프런트엔드 | React 19 | [React](../WebDevelopment/React.md) |
| 라우팅 | react-router-dom, `HashRouter` | [React Router](../WebDevelopment/React-Router.md) |
| 빌드 도구 | CRA(`react-scripts` 5.0.1) → Vite 검토 중 | [CRA → Vite](../WebDevelopment/CRA-vs-Vite.md) |
| 토큰 저장 | 브라우저 `localStorage` | [Token Storage](../Security/Token-Storage.md) |
| CORS | 와일드카드(`Access-Control-Allow-Origin: *`) | [CORS](../Network/CORS.md) |
| 배포 인프라 | Synology NAS Web Station, Let's Encrypt | [HTTPS & Mixed Content](../Network/HTTPS-and-Mixed-Content.md), [자체 호스팅 vs 클라우드](../Infrastructure/Self-Hosting-vs-Cloud.md) |

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
3. **문서화된 보안 결정과 실제 코드가 갈라진 지점이 실제로 존재한다.** `MEMO-WEB-02`가
   "인증 엔드포인트엔 CORS 와일드카드를 복사하지 말라"고 스스로 경고해뒀는데, 실제 구현
   (`response.php`의 공유 `allow_cors()`)은 그 경고를 지키지 못했다 — 다행히 인증 방식(헤더
   토큰)이 그 갭의 실질적 위험을 낮춰주고 있지만, 코드와 문서가 항상 일치하지는 않는다는 걸 보여주는
   실제 사례다.
4. **인프라 제약이 기술 선택을 여러 단계로 역산시켰다.** "이미 NAS가 있다" → "NAS가 MariaDB를
   기본 지원한다" → "로컬도 같은 Apache+PHP 조합(XAMPP)으로 맞춘다"로 이어지는 연쇄, 그리고
   "Web Station GUI로 rewrite 설정을 못 만진다" → "HashRouter로 우회한다"는 연쇄가 둘 다 같은
   NAS 선택 하나에서 갈라져 나왔다.
5. **"프레임워크가 없다"는 선택이 백엔드/프런트 양쪽에서 대칭적으로 나타난다.** 백엔드는 파일
   하나가 엔드포인트 하나, 프런트는 페이지 폴더 하나가 라우트 하나 — 서로 다른 언어인데 구조적
   철학이 같다. 두 계층을 서로 다른 세션에서 배웠는데도 나중에 보니 같은 패턴이었다는 게 이
   저장소를 순서대로 훑는 재미이기도 하다.

## 같이 보기 (문서 전체 지도)

- [RottenNobleProject 아키텍처 이해하기](./RottenNobleProject-Architecture.md) — 세션별 코드 학습 기록(1~3회차)
- [PHP](../WebDevelopment/PHP.md) · [MariaDB](../Database/MariaDB.md) · [Redis](../Infrastructure/Redis.md) — 백엔드 언어/저장소
- [JWT vs Redis 세션](../Security/JWT-vs-Redis-Session.md) · [비밀번호 해싱](../Security/Password-Hashing.md) ·
  [CORS](../Network/CORS.md) · [Token Storage](../Security/Token-Storage.md) — 인증/보안
- [REST API 설계](../WebDevelopment/REST-API-Design.md) — 백엔드-프런트 통신 규약
- [React](../WebDevelopment/React.md) · [React Router](../WebDevelopment/React-Router.md) · [CRA → Vite](../WebDevelopment/CRA-vs-Vite.md) — 프런트엔드
- [자체 호스팅 vs 클라우드](../Infrastructure/Self-Hosting-vs-Cloud.md) · [HTTPS & Mixed Content](../Network/HTTPS-and-Mixed-Content.md) — 인프라

## 참고자료

- `DevelopPrompt/CurrentProject/_RottenNobleProject/04_CURRENT_PROJECT.md` — 제품 정의, 엔드포인트 표
- `DevelopPrompt/CurrentProject/_RottenNobleProject/CODE_MEMO.md` — `MEMO-WEB-01`~`07` 전체
- `RottenNoble-Project`(`develop` 브랜치) — 실제 코드

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 개별 주제 문서 12개를 다 쓴 뒤 전체 그림을 한 문서로 종합 |
