# 방문자 Analytics

---

- **카테고리**: 웹 개발, 보안 (1~3개, 너무 잘게 쪼개지 않는다)
- **상태**: 완료
- **기준 시점**: 2026-09-13
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: `-`

---

## 출처

- `RottenNobleProject` `STUDY-03` — `DevelopPrompt/CurrentProject/_RottenNobleProject/Study.md`

## 정의

"방문자 analytics"는 웹사이트나 앱에 사람들이 어떻게 들어와서 무엇을 보고 가는지를 기록·집계하는
일 전반을 가리키는데, 실제로는 서로 목적이 다른 두 갈래로 나뉜다.

하나는 **웹 analytics(pageview 기반)**다 — "몇 명이 왔고, 어느 페이지를 봤고, 어디서 유입됐는지"를
본다. Google Analytics, Plausible, Umami 같은 도구가 여기 속한다. 다른 하나는 **제품
analytics(이벤트 기반)**다 — "사용자가 앱 안에서 어떤 행동을 했는지"를 임의의 이벤트 단위로
기록해서, 가입부터 결제까지의 퍼널이나 N일 후 재방문율(리텐션) 같은 걸 나중에 자유롭게 조합해서
본다. Mixpanel, Amplitude가 대표적이다. 여기에 더해 **BI(Business Intelligence) 툴**(Looker,
Tableau, Metabase, Superset)은 데이터를 수집하지 않는다 — 이미 어딘가(데이터 웨어하우스, RDB)에
쌓인 데이터를 SQL 등으로 조회해서 대시보드로 보여주는 "조회·시각화" 역할만 한다.

## 요약

Mixpanel 같은 이벤트 기반 product analytics는 "사용자가 무엇을 했는지"에 최적화되어 있고, BI 툴은
이미 모인 데이터를 다양한 각도로 재가공하는 도구다. 이 프로젝트가 만든 자체 analytics는 이 둘과는
다르게 "누가 어디서 왔고 어떤 경로를 봤는지"에 초점을 맞춘 pageview 기반 시스템이다 — 목적이
다르면 맞는 도구도 달라진다.

## 상세

### 왜 두 갈래로 나뉘었나

초기 웹 analytics(Google Analytics 원조, 그 전엔 Webalizer 같은 서버 로그 분석기)는 "몇 명이
어떤 페이지를 봤는지"를 집계하는 것에서 시작했다. 웹사이트는 대부분 "페이지"로 이루어져 있으니
페이지뷰가 자연스러운 측정 단위였다.

이후 모바일 앱과 SaaS 제품이 늘면서 상황이 달라졌다. 앱은 "페이지"가 아니라 "화면"과 "액션"으로
이루어져 있고, 제품팀이 진짜 알고 싶은 건 "이 버튼을 누른 사람 중 몇 %가 다음 단계로 넘어갔는지",
"가입 후 3일 안에 이 기능을 써본 사람이 한 달 후에도 남아있을 확률이 얼마나 높은지" 같은,
페이지뷰만으로는 답할 수 없는 질문이었다. 여기서 Mixpanel(2009년 창업), 이후 Amplitude 같은
이벤트 기반 product analytics가 자리를 잡았다.

### Mixpanel류가 동작하는 방식

이벤트 기반 도구는 미리 "무엇을 측정할지" 스키마를 정하지 않는다. 대신 코드 어디서든
`track("이벤트이름", { 속성1: 값1, 속성2: 값2 })` 형태로 임의의 이벤트를 그때그때 전송한다.
예를 들어 쇼핑몰이라면 `장바구니_추가`, `결제_시작`, `결제_완료` 같은 이벤트를 각 단계마다 보내고,
각 이벤트에는 사용자 식별자(로그인 전이면 익명 ID, 로그인 후엔 실제 user ID로 병합)와 상품
가격·카테고리 같은 속성이 딸려 온다.

이렇게 쌓인 raw event log를 바탕으로, Mixpanel UI에서 나중에 자유롭게 질문을 만들어 본다 — "장바구니
추가 이벤트를 한 사람 중 결제 완료까지 간 비율(퍼널)", "특정 이벤트를 한 사용자 그룹의 30일 리텐션"
같은 것들이다. 즉 **먼저 다 기록해두고, 나중에 필요한 걸 자유롭게 뽑아본다**는 게 핵심이다.

### BI 툴은 수집기가 아니라 조회기다

Looker, Tableau, Metabase, Superset 같은 BI 툴은 Mixpanel과 자주 혼동되지만 역할이 다르다.
이들은 이벤트를 직접 수집하지 않는다 — 이미 데이터 웨어하우스(BigQuery, Snowflake)나 RDB에 쌓인
데이터에 SQL 쿼리를 던져서 그 결과를 표·그래프로 보여주는 게 전부다. 그래서 실무에서는 흔히
Mixpanel/GA로 원본 이벤트를 모으고, 그 데이터를 웨어하우스로 옮긴 뒤(Mixpanel도 자체 export
기능이 있다) BI 툴로 마케팅팀·경영진이 보기 편한 대시보드를 다시 만드는 조합을 쓴다.

### 이 프로젝트(RottenNobleProject)가 택한 방식

이 블로그의 백엔드(`backend-spring/.../analytics/`)는 pageview 단위로 기록한다 — 방문한 경로,
유입 referrer, IP에서 뽑은 국가/도시/소속조직(회사 네트워크 등), 기기 종류. `visitor_id`(브라우저
localStorage, 장기 보관)로 총방문자·재접속 여부를 세고, `visit_id`(sessionStorage, 탭 단위)로
한 번의 방문 안에서 어떤 경로를 거쳤는지 재구성한다.

이건 Mixpanel처럼 "임의 이벤트"를 자유롭게 추적하는 구조가 아니라, 미리 정한 필드(경로/유입/지역)만
보는 구조라는 점에서 GA/Plausible 같은 **웹 analytics**에 더 가깝다. 나중에 "특정 버튼 클릭",
"방명록 작성 완료" 같은 임의 이벤트까지 보고 싶어지면, 지금 구조를 갈아엎지 않고 `event_name` +
`properties`(JSON) 컬럼을 가진 별도 테이블을 추가하는 방향으로 확장할 수 있다 — Mixpanel이 하는
일을 축소판으로 직접 만드는 셈이다.

### 프라이버시 설계의 차이

Mixpanel/GA4/Amplitude 같은 상용 SaaS는 데이터가 벤더의 해외 서버에 쌓이고, 방문자 식별을 위해
쿠키나 기기 식별자를 쓴다. 그래서 한국 개인정보보호법이나 GDPR 기준으로 해외 이전 고지, 쿠키 동의
배너가 필요해진다. 이 프로젝트의 자체 구현이나 Plausible/Umami/Matomo 같은 self-hosted
오픈소스는 데이터가 자기 서버를 벗어나지 않아 이 부담이 크게 줄어든다 — 이 프로젝트가 상용 SaaS
대신 자체 구현을 택한 이유 중 하나다.

## 비교표

| 항목 | 이 프로젝트 자체 구현 | Mixpanel / Amplitude | Google Analytics (GA4) | Plausible / Umami (self-hosted) | BI 툴 (Metabase / Superset) |
|---|---|---|---|---|---|
| 추적 단위 | pageview(경로 단위) | 임의 이벤트(자유 정의) | 이벤트+pageview 혼합 | pageview | 없음 — 수집하지 않음 |
| 데이터 위치 | 자체 서버(NAS) | 벤더 클라우드(해외) | 구글 클라우드(해외) | self-host 시 자체 서버 | 연결한 DB/웨어하우스 |
| 개인정보/쿠키 부담 | 낮음 (IP 미저장, 쿠키 없음) | 높음 (해외 이전·동의 필요) | 높음 (해외 이전·동의 필요) | 낮음 (쿠키 없는 옵션) | 해당 없음 |
| 주 용도 | 방문 추적, 유입경로 확인 | 제품 사용 퍼널/리텐션 분석 | 범용 웹/앱 트래픽 분석 | 경량 웹 트래픽 분석 | 이미 있는 데이터 재가공·시각화 |
| 비용 | 무료(자체 인프라) | 유료(이벤트 수 기준 과금) | 무료(표준), 유료(360) | 무료(self-host) 또는 유료(SaaS) | 무료(오픈소스판) |

## 질문

- **Q. Mixpanel 같은 이벤트 기반 analytics가 이 프로젝트의 pageview 기반보다 "더 좋은" 도구인가?**
  A. 아니다, 목적이 다르다. "얼마나 많은 사람이 어디서 왔는지"만 알면 되는 개인 블로그엔 pageview
  기반이 더 단순하고 충분하다. "가입 후 어떤 행동을 해야 재방문율이 높아지는지" 같은 제품 최적화
  질문이 생기는 순간부터 이벤트 기반이 필요해진다.

- **Q. BI 툴을 쓰면 Mixpanel 같은 이벤트 수집 도구가 필요 없어지는 건가?**
  A. 아니다, 반대다. BI 툴은 수집을 안 하기 때문에 뭔가가 먼저 데이터를 모아둬야 한다. 실무에서는
  Mixpanel/GA가 모은 원본 데이터를 웨어하우스로 옮긴 뒤 BI 툴로 재가공하는 조합이 흔하다.

## 예시 코드

이 프로젝트의 pageview 기록 흐름 — IP는 지역/조직 조회에만 잠깐 쓰이고 어디에도 저장되지 않는다.

```java
// backend-spring/.../service/AnalyticsService.java
String ip = ClientIpResolver.resolve(httpRequest);
GeoLookupResult geo = geoIpService.lookup(ip);
// ip는 이 지점 이후로 다시 쓰이지 않는다 — 저장 안 함.

PageView pageView = new PageView();
pageView.setCountry(geo.country());
pageView.setRegionCity(geo.regionCity());
pageView.setOrgName(geo.orgName()); // 방문자가 속한 네트워크(회사 등)의 조직명
```

Mixpanel류였다면 같은 상황을 대략 이렇게 다뤘을 것이다(실제 이 프로젝트 코드가 아니라 개념
예시):

```javascript
// Mixpanel 스타일 이벤트 기반 추적 (개념 예시)
mixpanel.track("페이지_조회", {
  경로: "/resume",
  유입태그: "companyA",
});
// 나중에 Mixpanel UI에서: "유입태그=companyA인 사람 중 /resume을 본 사람의 비율" 같은 질문을
// 이벤트를 다시 보내지 않고도 자유롭게 만들어 볼 수 있다.
```

## 실무

- 스타트업/제품팀은 Mixpanel·Amplitude(제품 사용 분석)와 GA4(마케팅/유입 분석)를 같이 쓰는 경우가
  많고, 데이터가 커지면 원본 이벤트를 BigQuery·Snowflake 같은 웨어하우스로 옮겨 Looker·Tableau로
  다시 대시보드를 만드는 구조가 흔하다.
- 개인 프로젝트나 트래픽이 적은 사이트는 self-hosted(Plausible·Umami·Matomo) 또는 직접 구현이
  비용과 프라이버시 부담 면에서 더 합리적이다 — 이 프로젝트가 택한 방향.
- 최근 동향(2026년 기준): 쿠키 없는(cookieless) analytics 수요가 늘며 Plausible·Fathom·Simple
  Analytics 같은 "GA4 대체제"가 자리를 잡았고, GA4 자체도 EU 등 지역에서 Consent Mode 요구가
  강화되는 추세다.

## 같이 보기

- [RottenNobleProject 아키텍처 이해하기](../Architecture/RottenNobleProject-Architecture.md)

## 참고자료

- [Mixpanel — 공식 사이트](https://mixpanel.com/)
- [Amplitude — 공식 사이트](https://amplitude.com/)
- [Plausible Analytics — 공식 사이트](https://plausible.io/)
- [Umami — 공식 사이트](https://umami.is/)
- [Matomo — 공식 사이트](https://matomo.org/)
- [MaxMind GeoLite2 — 공식 문서](https://dev.maxmind.com/geoip/geolite2-free-geolocation-data)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-13 | 최초 작성 | RottenNobleProject에 방문자 analytics를 직접 구현하며, Mixpanel/BI 툴과 이 자체 구현이 어떻게 다른지 궁금해져서 작성 |
