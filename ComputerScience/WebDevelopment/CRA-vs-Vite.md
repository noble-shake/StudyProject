# CRA(Create React App) → Vite 마이그레이션

---

- **카테고리**: 웹 개발, 프런트엔드 빌드 도구
- **상태**: 완료
- **기준 시점**: 2026-09-08
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: -

---

## 출처

- `RottenNobleProject` `STUDY-02` — `DevelopPrompt/CurrentProject/_RottenNobleProject/Study.md`

## 정의

React 앱을 만들 때, React 코드(JSX)를 브라우저가 이해할 수 있는 JS로 변환하고, 여러 파일을 하나로
묶고(번들링), 개발 중엔 변경사항을 즉시 반영해주는 도구가 필요하다 — 이런 일을 해주는 게 "빌드
도구"다. Create React App(CRA)과 Vite는 둘 다 이 역할을 하는 도구지만, 내부에서 쓰는 기술과
설계 철학이 다르다. CRA는 Webpack을, Vite는 네이티브 ES 모듈과 esbuild/Rollup을 기반으로 한다.

## 요약

CRA는 2022년 이후 사실상 유지보수가 끊긴 도구인데, RottenNobleProject는 이미 그 대가로 실제 버그를
겪었다(`react-router-dom`을 테스트에서만 못 찾는 문제) — React 자체를 바꾸는 게 아니라, React를
감싸는 빌드 도구만 Vite로 바꾸면 이 문제 자체가 사라진다.

## 상세

### CRA가 왜 생겼고, 왜 저물었나

2016년 등장한 CRA는 "Webpack 설정을 하나도 몰라도 `npx create-react-app`만 치면 React 개발을
바로 시작할 수 있다"는 게 핵심 가치였다. 당시엔 획기적이었다 — Webpack 설정 파일을 처음부터
직접 작성하는 건 상당한 학습 곡선이 있었기 때문이다. 하지만 시간이 지나며 두 가지 일이 동시에
일어났다. 첫째, React 생태계 자체가 CRA 없이도 쉽게 시작할 수 있는 대안(Vite 등)을 갖추게 됐다.
둘째, CRA를 유지보수하던 팀의 활동이 사실상 멈췄다 — 마지막 주요 릴리스(`react-scripts` 5.0.1)가
2022년에 나온 뒤로 큰 업데이트가 없다. 그 결과 React 공식 문서도 이제 신규 프로젝트에 CRA를
권장하지 않는 쪽으로 안내를 바꿨다.

### 실제로 겪은 문제 — `exports` 필드와 Jest

이 프로젝트가 CRA의 노후화를 추상적으로만 아는 게 아니라 **실제로 부딪힌** 지점이 있다.
`react-router-dom`(v6/v7)을 앱에 붙였는데, 화면은 멀쩡히 뜨지만(`npm start`) 테스트만 실행하면
(`npm test`) 이런 에러로 죽었다:

```
Cannot find module 'react-router/dom' from 'node_modules/react-router-dom/dist/index.js'
```

원인은 이렇다. 최신 npm 패키지들은 `package.json`의 `exports` 필드로 "이 패키지의 어느 경로를
import하면 실제로 어느 파일이 로드되는지"를 명시적으로 매핑한다. `react-router-dom`도 이 방식을
쓴다. **개발 서버(webpack 5)는 이 `exports` 필드를 정상적으로 읽지만**, CRA(`react-scripts 5.0.1`)
안에 번들된 Jest 버전은 이 필드를 이해하지 못하고 옛날 방식(`package.json`의 `main` 필드)으로만
모듈을 찾다가 실패한다. 즉, 같은 코드가 화면에서는 되고 테스트에서는 안 되는 상황이 벌어진 것 —
이건 `react-router-dom`이라는 라이브러리의 버그가 아니라, **CRA가 최신 패키지 생태계의 관례를
못 따라가고 있다는 증거**다. 버전을 내려도(v6로) 다른 패키지에서 같은 계열 문제가 또 나올 수
있다는 뜻이기도 하다.

당장의 대응은 "라우터를 쓰는 컴포넌트는 CRA 테스트 대상에서 빼고, 라우터를 안 거치는 순수 로직만
테스트한다"였다 — 근본 원인을 고치는 게 아니라 우회한 것이다.

### Vite가 이 문제를 원천적으로 안 겪는 이유

Vite는 애초에 설계 자체가 다르다. 개발 중에는 브라우저의 네이티브 ES 모듈(`import`) 기능을 그대로
활용해서 번들링 없이 파일을 그대로 서빙하고(그래서 개발 서버 시작이 즉각적이다), 프로덕션
빌드에는 Rollup을 쓴다. 테스트 러너로는 보통 Vitest를 같이 쓰는데, Vitest는 Vite와 같은 모듈
해석 엔진을 공유하기 때문에 `exports` 필드 같은 최신 패키지 관례를 처음부터 정확히 지원한다 —
"webpack은 되는데 Jest는 안 되는" 종류의 불일치 자체가 생길 구조가 아니다.

### 검토했지만 채택하지 않은 대안들

- **React를 다른 프레임워크(Vue, Svelte)로 교체** — 검토 범위 밖으로 판단했다. 이 프로젝트의 목표
  자체가 "React를 실제로 익히는 것"이라, React를 바꾸는 건 학습 목적과 정면으로 어긋난다. 문제는
  React가 아니라 그걸 감싼 빌드 도구였다는 걸 구분하는 게 중요하다.
- **Next.js로 전환** — Next.js는 프런트엔드뿐 아니라 API 라우트까지 갖는 풀스택 프레임워크다.
  하지만 이 프로젝트는 "PHP 백엔드를 별도로 두고 그걸 직접 익힌다"는 목표가 있어서, 백엔드
  역할까지 흡수하는 Next.js는 오히려 이 프로젝트의 학습 목표와 충돌한다.
- **`craco`/`react-app-rewired`로 CRA의 Jest 설정만 오버라이드** — 가능은 하지만, 이것도 결국
  "낡은 도구 위에 패치를 얹는" 접근이라 이 프로젝트 규모에서 들일 만한 복잡도는 아니라고 보류했다.

## 비교표

| 항목 | CRA (`react-scripts`, 현재 사용 중) | Vite |
|---|---|---|
| 내부 번들러 | Webpack 5 | 개발: 네이티브 ESM / 빌드: Rollup |
| 개발 서버 시작 속도 | 프로젝트 규모에 비례해 느려짐 | 파일을 그대로 서빙해 훨씬 빠름 |
| `package.json exports` 필드 지원 | 개발 서버는 지원, 번들된 Jest는 미지원 | 네이티브로 지원 |
| 유지보수 상태 | 사실상 중단(마지막 주요 릴리스 2022) | 활발히 유지보수 중 |
| React 공식 문서 권장 여부 | 신규 프로젝트에 비권장 | 대안으로 언급됨 |
| 이 프로젝트가 실제로 겪은 문제 | `react-router-dom` 테스트 실패(`exports` 미지원) | (해당 문제 없음) |

## 질문

- **Q. 지금 당장 문제가 있는 건 아닌데(우회책으로 넘어감), 굳이 마이그레이션이 필요한가?**
  A. `Study.md`의 철학대로, 이건 "지금 당장 처리해야 할 일"이 아니라 "언젠가 제대로 배우고
  판단하고 싶은 후보"로 남겨둔 것이다. 다만 CRA가 유지보수되지 않는다는 사실 자체는 시간이
  지날수록(새 라이브러리를 더 붙일수록) 같은 계열 문제가 반복될 가능성을 키운다 — 언제
  마이그레이션할지는 별도 판단이 필요하지만, "왜 필요할 수도 있는지"는 이미 실측으로 확인됐다.
  **(2026-09-09 갱신) 실제로 마이그레이션이 이루어졌다** — 백엔드를 Spring Boot로 전면
  재작성하는 김에 프런트 빌드 도구도 같이 옮겼다. 결과: `npm install` 의존성 개수가
  1188개 → 64개로 줄었고, 위에서 겪은 `react-router-dom`/Jest `exports` 문제 자체가 재현되지
  않는다(Vite+Vitest 조합에선 이 문제가 애초에 발생할 구조가 아니라는 "Vite가 이 문제를
  원천적으로 안 겪는 이유" 절의 설명이 실측으로 확인됨).

- **Q. CRA에서 Vite로 옮기면 코드를 얼마나 고쳐야 하나?**
  A. React 컴포넌트 코드 자체는 거의 그대로 유지된다. 주로 바뀌는 건 환경변수 접근 방식
  (`process.env.REACT_APP_*` → `import.meta.env.VITE_*`), `public/index.html`의 스크립트
  주입 방식, 그리고 `package.json`의 `proxy` 필드 대신 Vite의 `server.proxy` 설정으로 옮기는
  작업이다. 이 프로젝트는 `REACT_APP_API_BASE_URL`을 여러 곳에서 쓰고 있어(`frontend/src/api/*.js`),
  환경변수 이름 변경이 실제 마이그레이션 작업의 상당 부분을 차지할 것으로 보인다.

## 예시 코드

```json
// 현재: package.json (CRA)
"scripts": {
  "start": "react-scripts start",
  "build": "react-scripts build",
  "test": "react-scripts test"
}
```

```js
// Vite로 옮기면 환경변수 접근 방식이 바뀐다
// CRA: process.env.REACT_APP_API_BASE_URL
// Vite: import.meta.env.VITE_API_BASE_URL
const API_BASE_URL = import.meta.env.VITE_API_BASE_URL;
```

## 플로우차트

(생략 — "번들러가 다르다"는 이 주제의 핵심이 도구 하나를 다른 도구로 치환하는 것뿐이라 순서·분기가
없다. 표로 이미 충분하다.)

## 실무

실무에서는 이미 Vite가 새 React 프로젝트의 사실상 표준 스캐폴딩 도구로 자리잡았다 — React 공식
문서의 "시작하기" 안내도 CRA 대신 Vite(또는 Next.js 같은 프레임워크)를 언급하는 쪽으로 바뀌었다.
기존에 CRA로 시작한 대규모 프로젝트들은 당장 마이그레이션하지 않고 유지보수 모드로 두는 경우도
많지만, 새로 시작하는 프로젝트에서 CRA를 고르는 경우는 실무에서 거의 사라졌다. 이 프로젝트처럼
"이미 CRA로 시작했고, 실제 문제를 한 번 겪었다"는 상황은 마이그레이션을 진지하게 고려할 만한 신호에
해당한다.

## 같이 보기

- [PHP](./PHP.md) — 이 프로젝트의 백엔드. Next.js를 검토하지 않은 이유(백엔드 학습 목표와 충돌)와
  연결된다

## 참고자료

- [Vite 공식 문서](https://vitejs.dev/)
- [React 공식 문서 — 새 프로젝트 시작하기](https://react.dev/learn/start-a-new-react-project)
- `DevelopPrompt/Web/08_PITFALLS.md` §2 — 이 프로젝트에서 실측한 CRA Jest `exports` 문제 원문

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성, `STUDY-02` 학습 완료로 표시 | `Study.md`의 STUDY-02 항목을 실제로 파고들어 정리 |
| 2026-09-09 | 마이그레이션 실제 완료·프로덕션 배포·의존성 개수 실측(1188→64) 반영 | 백엔드 Spring Boot 재작성과 함께 프런트 빌드 도구도 같이 전환됨 |
