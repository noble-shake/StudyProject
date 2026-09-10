# 헤드리스 브라우저로 로컬에서 화면 검증하기 — Playwright

---

- **카테고리**: 웹 개발, 테스트
- **상태**: 완료
- **기준 시점**: 2026-09-10, Playwright 1.63 기준
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: -

---

## 출처

`RottenNoble-Project`는 `develop` 브랜치에 푸시하면 GitHub Actions가 곧바로 프로덕션에
빌드+배포한다 — 스테이징 환경이 없다. 세션에 Node.js조차 없던 시기엔 "코드 수정 → PR →
`develop` 머지(=라이브 배포) → 눈으로 확인"이라는 위험한 루프를 돌 수밖에 없었다. Node를
설치한 김에, 실제로 배포하지 않고도 화면이 어떻게 나오는지 확인하는 방법을 정리했다.

## 정의

헤드리스 브라우저(headless browser)는 화면 창을 띄우지 않고 백그라운드에서 실행되는 브라우저다.
사람이 보는 GUI는 없지만, 페이지를 렌더링하고 자바스크립트를 실행하는 엔진 자체는 일반
브라우저와 동일하다. Playwright는 이 헤드리스 브라우저(Chromium/Firefox/WebKit)를 코드로
조작할 수 있게 해주는 자동화 라이브러리로, 페이지 이동·클릭·입력·스크린샷·콘솔 로그 수집 같은
동작을 스크립트로 짤 수 있다.

## 요약

`npm run build`가 성공한다고 해서 화면이 의도한 대로 나온다는 보장은 없다 — 컴파일 성공과
시각적 정확성은 서로 다른 질문이다. `npm run dev`로 띄운 개발 서버를 Playwright의 headless
Chromium으로 열어 스크린샷을 찍고 브라우저 콘솔 에러를 확인하는 방식으로, GUI가 없는 서버성
세션 환경에서도 "실제로 어떻게 보이는지"를 배포 전에 직접 확인할 수 있었다.

## 상세

### 왜 `npm run build`만으로는 부족한가

`npm run build`(또는 `vite build`)는 자바스크립트/CSS 문법 오류, import 경로 오류 같은
**컴파일 단계의 문제**만 잡아준다. 색상값 실수, 레이아웃이 깨지는 문제, 조건부 렌더링이 의도한
분기를 안 타는 문제 같은 **시각적/논리적 문제**는 빌드가 성공해도 얼마든지 남아있을 수 있다.
이 세션에서도 배경 셰이더의 파스텔 블루 색감이나 블러 대비가 "적당한지"는 코드만 봐서는 판단할
수 없었고, 실제로 렌더링된 화면을 봐야 했다([절차적 배경 셰이더](../Graphics/Procedural-Noise-Shaders.md)
참고).

### 개발 서버를 백그라운드로 띄우고 포트가 열릴 때까지 기다리기

무작정 `sleep 5` 후에 접속을 시도하면, 서버가 그보다 느리게 뜨는 환경에서는 실패하고 빠르게
뜨는 환경에서는 시간을 낭비한다. 대신 **포트가 실제로 응답할 때까지 짧은 간격으로 폴링**한다:

```bash
npm run dev -- --port 5173 --strictPort > vite-dev.log 2>&1 &
timeout 30 bash -c 'until curl -sf http://localhost:5173 >/dev/null; do sleep 1; done'
```

`--strictPort`는 지정한 포트가 이미 쓰이고 있으면 다른 포트로 슬쩍 옮겨가는 대신 바로 실패하게
만든다 — 스크립트가 어느 포트를 열었는지 모른 채 헤매는 상황을 막아준다.

### Playwright로 페이지 열고 스크린샷 찍기

```javascript
import { chromium } from 'playwright';

const browser = await chromium.launch({ args: ['--no-sandbox'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 800 } });

const errors = [];
page.on('console', (msg) => { if (msg.type() === 'error') errors.push(msg.text()); });
page.on('pageerror', (err) => errors.push(String(err)));

await page.goto('http://localhost:5173/#/', { waitUntil: 'networkidle' });
await page.waitForSelector('text=게시판 보기', { timeout: 10000 });
await page.screenshot({ path: 'home.png' });
```

`waitForSelector`로 "이 화면이 완전히 그려졌다"는 확실한 신호(특정 텍스트가 나타남)를 기다린
뒤 스크린샷을 찍는 게 핵심이다 — `waitUntil: 'networkidle'`만 믿으면 클라이언트 사이드
렌더링이 아직 안 끝난 시점의 빈 화면을 찍을 위험이 있다. `console`/`pageerror` 이벤트를
모아두면, 화면은 그려졌지만 내부적으로 자바스크립트 에러가 나고 있는 경우(겉보기엔 멀쩡해
보이는 실패)까지 잡아낼 수 있다.

### 백엔드 없이 프런트만 검증하기 — API 실패를 정상으로 구분하는 법

이 세션에는 로컬에 Spring Boot 백엔드/MariaDB/Redis가 없었다. `/posts` 화면을 스크린샷으로
찍었을 때 "게시글 목록을 불러오지 못했습니다: Unexpected token '<', ... is not valid JSON"이라는
에러가 그대로 찍혔는데, 이건 배경 셰이더나 블러 코드의 버그가 아니라 **API 서버가 없어서 fetch가
Vite 개발 서버의 index.html(HTML)을 대신 받아버린, 예상된 실패**였다. 이런 상황에서 "에러가
찍혔다 = 버그"로 성급히 판단하지 않으려면, 그 에러가 지금 검증하려는 대상(배경/레이아웃)과
무관한 원인(백엔드 부재)에서 왔는지를 먼저 구분해야 한다. 반대로 브라우저 콘솔에 자바스크립트
에러가 하나도 없다는 사실은, 적어도 프런트 코드 자체는 깨지지 않았다는 걸 보여주는 유효한
증거였다.

### 세션이 끝나면 dev 서버 프로세스를 반드시 정리해야 하는 이유

`npm run dev &`로 백그라운드에 띄운 프로세스는 셸이 끝나도 살아있을 수 있다. 다음에 같은
포트로 다시 띄우려 하면 `EADDRINUSE`(포트 사용 중) 에러로 실패한다. `$!`로 받은 PID는
npm 래퍼 프로세스일 뿐, 실제 vite 서버에는 SIGTERM이 전달되지 않는 경우가 있어서, 포트를
직접 리슨하는 프로세스를 찾아 종료하는 게 확실하다:

```bash
netstat -ano | grep ":5173" | grep LISTENING   # PID 확인
taskkill //F //PID <그 PID>                     # Windows
# 또는: lsof -ti:5173 -sTCP:LISTEN | xargs -r kill   # Unix 계열
```

## 비교표

| 방식 | 확인 시점 | 백엔드 연동 검증 | 비용 |
|---|---|---|---|
| 라이브 배포 후 눈으로 확인 | 배포 완료 후(늦음) | 가능(실제 프로덕션 API) | 배포 파이프라인 1~2분 + 버그면 되돌리는 비용 |
| Playwright 로컬 스크린샷(이 방식) | 배포 전 | 불가능(백엔드가 없으면) — 프런트 단독 검증만 | 개발 서버 기동 몇 초 + 스크립트 실행 몇 초 |
| 진짜 스테이징 서버 | 배포 전 | 가능(스테이징 API와 연동) | 별도 인프라(도메인/컨테이너) 구축·유지 비용 |

## 질문

- **Q. `chromium-cli`라는 전용 도구가 있다고 들었는데 왜 안 썼나?**
  A. 이 작업 환경에는 그 도구가 설치돼 있지 않았다. 대신 `npx`로 Playwright를 그 자리에서
  설치해 직접 스크립트를 짜서 대체했다 — Playwright의 `chromium.launch()` API는 `chromium-cli`
  같은 REPL 도구가 내부적으로 쓰는 것과 같은 엔진이라, 기능적으로는 동등한 검증이 가능했다.

- **Q. headless라면서 왜 창이 하나도 안 뜨는데 스크린샷이 찍히나?**
  A. 헤드리스 브라우저도 내부적으로는 페이지를 완전히 렌더링한다 — 다만 그 렌더링 결과를
  모니터에 그려서 사람이 보게 하는 대신, 프로그램이 이미지 파일로 저장하도록 요청할 수 있을
  뿐이다. "화면에 안 보인다"와 "렌더링을 안 한다"는 다른 이야기다.

## 예시 코드

이 세션에서 실제로 쓴 검증 스크립트의 핵심 부분(홈 화면과 게시판 화면 두 곳을 확인):

```javascript
await page.goto(`${base}/#/`, { waitUntil: 'networkidle' });
await page.waitForSelector('text=게시판 보기', { timeout: 10000 });
await page.waitForTimeout(1500); // 셰이더 애니메이션이 몇 프레임 진행되도록
await page.screenshot({ path: `${outDir}/home.png` });

await page.goto(`${base}/#/posts`, { waitUntil: 'networkidle' });
await page.waitForSelector('text=게시판', { timeout: 10000 });
await page.waitForTimeout(1500);
await page.screenshot({ path: `${outDir}/posts.png` });

console.log('CONSOLE_ERRORS:', JSON.stringify(errors));
```

애니메이션이 있는 화면(이 경우 시간에 따라 흐르는 배경 셰이더)을 검증할 때는 `waitForTimeout`
으로 몇 프레임 진행될 시간을 준 뒤 찍어야, 첫 프레임의 정지된 모습만 보고 판단하는 실수를
피할 수 있다.

## 플로우차트

(생략 — "서버 띄우기 → 포트 대기 → 브라우저로 열기 → 스크린샷/콘솔 확인 → 서버 정리"라는
단일 순서라 위 설명만으로 충분히 전달된다.)

## 실무

CI 파이프라인에서 Playwright/Cypress 같은 도구로 스크린샷을 찍어 이전 버전과 자동 비교하는
"시각적 회귀 테스트"(예: Percy, Chromatic, Playwright의 자체 스냅샷 비교 기능)는 실무에서
흔하다. 다만 이 문서의 방식은 그런 자동화된 회귀 테스트가 아니라 **사람이 "이번에 바뀐 게
의도대로 보이는지" 한 번 확인하기 위한 임시 검증**에 가깝다 — 백엔드 연동, 실제 사용자 인증
흐름, 여러 브라우저/기기 대응까지 확인하려면 결국 진짜 스테이징 환경이 필요하다는 한계는
분명히 하고 넘어가야 한다.

## 같이 보기

- [절차적 배경 셰이더](../Graphics/Procedural-Noise-Shaders.md) — 이 방법으로 실제 검증한 셰이더
- [CRA → Vite](./CRA-vs-Vite.md) — 여기서 띄운 개발 서버(`npm run dev`)를 제공하는 빌드 도구

## 참고자료

- Playwright 공식 문서 (playwright.dev)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-10 | 최초 작성 | 스테이징 환경 없이 배경 셰이더 변경을 로컬에서 검증한 세션을 정리 |
