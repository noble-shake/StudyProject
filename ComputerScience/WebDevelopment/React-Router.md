# React Router — HashRouter vs BrowserRouter

---

- **카테고리**: 웹 개발, 프런트엔드
- **상태**: 완료
- **기준 시점**: 2026-09-08, react-router-dom v7 기준
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNobleProject` — `CODE_MEMO.md`의 `MEMO-WEB-05`, `RottenNobleProject-Architecture.md`
2회차(아키텍처 계층)에서 나온 주제.

## 정의

React는 원래 "페이지 이동"이라는 개념이 없다 — 하나의 HTML 페이지 안에서 컴포넌트를 바꿔치기하는
방식(SPA, Single Page Application)이 기본이다. React Router는 이 SPA 안에서 "URL이 이렇게
바뀌면 이 컴포넌트를 보여준다"는 규칙을 정의할 수 있게 해주는 라이브러리다. 이때 URL을 실제로
어떻게 관리할지에 두 가지 방식이 있는데, 하나가 `BrowserRouter`(진짜 URL 경로를 씀), 다른 하나가
`HashRouter`(URL에 `#`을 붙여 그 뒤를 씀)다.

## 요약

이 프로젝트는 원래 `BrowserRouter`를 쓰려 했지만, Synology Web Station에서 "알 수 없는 경로는
`index.html`로 돌려보내라"는 서버 설정(rewrite rule)을 만질 방법을 못 찾아서, 서버 설정이 아예
필요 없는 `HashRouter`로 우회했다 — URL에 `#`이 붙는 걸 감수하고 인프라 제약을 회피한 사례다.

## 상세

### 왜 `BrowserRouter`는 서버 설정이 필요한가

`BrowserRouter`를 쓰면 URL이 `https://rotten-noble.com/posts/3`처럼 진짜 경로처럼 보인다. 이건
자바스크립트의 History API를 이용해서, 실제로는 페이지를 새로 안 불러오면서 브라우저 주소창의
URL만 바꾸는 방식이다. 문제는 **사용자가 그 URL을 새로고침하거나, 그 링크로 직접 접속**할 때
생긴다 — 이때는 브라우저가 서버에 진짜로 `/posts/3`이라는 경로를 요청한다. 하지만 서버(Apache)
입장에서는 `/posts/3`이라는 실제 파일이나 폴더가 없다 — 이건 오직 React Router가 자바스크립트로
해석해야 하는 "가짜 경로"이기 때문이다. 그래서 서버가 반드시 "이런 알 수 없는 경로는 그냥
`index.html`을 대신 응답해라"는 **rewrite 규칙**을 갖고 있어야, React 앱이 로드된 뒤 React
Router가 그 경로를 보고 알맞은 컴포넌트를 보여줄 수 있다.

### 이 프로젝트가 부딪힌 것 — Web Station GUI의 한계

`MEMO-WEB-05`에 남은 이유는 이렇다: Nginx나 Apache의 rewrite 설정을 직접 만지려면 보통 설정
파일에 직접 규칙을 써야 하는데, Synology DSM의 Web Station GUI에는 이런 세밀한 rewrite 규칙을
직접 넣을 방법이 마땅치 않았다. 방법이 아예 없는 건 아닐 수 있지만(예: Web Station이 커스텀
설정 파일을 지원하는 버전으로 업데이트되면 가능할 수도 있음), 지금 당장 찾은 방법으로는
막혀 있었다.

### `HashRouter`가 이 문제를 피하는 방법

```jsx
// frontend/src/App.js
import { HashRouter, Routes, Route } from 'react-router-dom';

function App() {
  return (
    <HashRouter>
      <Routes>
        <Route path="/" element={<PostList />} />
        <Route path="/posts/:id" element={<PostDetail />} />
      </Routes>
    </HashRouter>
  );
}
```

`HashRouter`를 쓰면 URL이 `https://rotten-noble.com/#/posts/3`처럼 된다. 핵심은 **`#` 뒤에
오는 부분은 브라우저가 서버로 아예 전송하지 않는다**는 URL 스펙 자체의 성질이다. 브라우저는
`https://rotten-noble.com/#/posts/3`을 새로고침해도, 서버에는 그냥 `https://rotten-noble.com/`
(`#` 앞부분)만 요청한다 — 서버는 항상 같은 `index.html` 하나만 서빙하면 되고, `#` 뒤의 경로
해석은 전적으로 브라우저 안의 자바스크립트(React Router)가 담당한다. 그래서 서버 쪽에 어떤
rewrite 설정도 필요 없다.

### 감수한 대가

URL에 `#`이 보이는 건 사용자 경험 관점에서 약간의 단점이다 — 일부 사용자에게는 "덜 정돈된"
URL로 보일 수 있고, `#` 이후 부분은 검색엔진 크롤러가 예전에는 잘 못 읽던 시절도 있었다(지금은
구글 등 주요 크롤러가 처리하지만, 모든 도구가 동등하게 지원하는 건 아니다). `MEMO-WEB-05`는
이걸 "지금은 URL에 `#`이 붙는 것을 감수하고 우회한 상태"라고 명시적으로 기록해뒀고, 나중에
Web Station에서 rewrite 설정을 직접 만질 방법을 찾으면 `BrowserRouter`로 되돌리는 걸 재검토할
수 있다고 남겨뒀다 — 영구적인 결정이 아니라 "지금 찾은 방법으로는 이게 최선"이라는 임시 우회임을
분명히 한 것이다.

## 비교표

| 항목 | `HashRouter` (이 프로젝트) | `BrowserRouter` |
|---|---|---|
| URL 형태 | `example.com/#/posts/3` | `example.com/posts/3` |
| 서버 rewrite 설정 필요 여부 | 불필요 | 필요(알 수 없는 경로 → `index.html`) |
| 새로고침/직접 접속 시 동작 | 항상 안전(서버는 `#` 이전만 봄) | rewrite 설정 없으면 404 |
| 검색엔진 최적화(SEO) | 상대적으로 불리(과거 이력 때문에 도구 지원이 갈릴 수 있음) | 유리(일반 URL 구조) |
| 이 프로젝트가 고른 이유 | Web Station GUI로 rewrite 설정 불가 | (원래 의도했으나 인프라 제약으로 포기) |

## 질문

- **Q. `HashRouter`를 쓰면 정말 서버 설정을 하나도 안 만져도 되나?**
  A. 그렇다 — 이게 정확히 이 방식을 고른 이유다. 서버는 `/`(루트) 하나만 응답할 수 있으면
  되고, 그 안의 모든 경로 해석은 클라이언트(브라우저의 React Router)가 담당한다. 인프라를
  건드릴 권한이나 방법이 제한적인 환경(공유 호스팅, GUI만 제공하는 관리 콘솔 등)에서 SPA
  라우팅을 붙일 때 흔히 쓰이는 우회법이다.

- **Q. Web Station이 나중에 rewrite 설정을 지원하게 되면 정말 `BrowserRouter`로 바꿔야 하나?**
  A. `MEMO-WEB-05`는 그럴 가능성을 열어뒀지만 필수는 아니다. `HashRouter`도 기능적으로는
  완전히 동작하고 있고, 개인 블로그 규모에서 SEO(검색엔진 노출)가 핵심 목표가 아니라면 URL의
  `#` 하나 때문에 마이그레이션 비용을 들일 필요는 크지 않다 — 다만 만약 이 프로젝트가 나중에
  검색 노출이 중요한 방향으로 바뀐다면 재검토할 만한 항목이다.

## 예시 코드

```jsx
// 만약 BrowserRouter를 쓴다면 이렇게 바뀌고
import { BrowserRouter } from 'react-router-dom';
// <HashRouter> → <BrowserRouter>로 컴포넌트 하나만 바꾸면 코드 자체는 끝난다

// 하지만 서버(Apache) 쪽에 이런 rewrite 규칙이 반드시 있어야 한다 (.htaccess 예시)
// RewriteEngine On
// RewriteCond %{REQUEST_FILENAME} !-f
// RewriteRule ^ index.html [QSA,L]
```

## 플로우차트

(생략 — "URL의 `#` 앞/뒤를 서버가 보는지 안 보는지"라는 단일 차이가 핵심이라, 위 설명과 비교표로
충분히 전달된다.)

## 실무

실무에서는 새 프로젝트라면 대부분 `BrowserRouter`(또는 그 후속인 `createBrowserRouter`)를
기본으로 쓴다 — Vercel, Netlify 같은 정적 호스팅 플랫폼들은 애초에 "알 수 없는 경로는
index.html로"라는 rewrite 규칙을 기본 설정이나 한 줄짜리 설정 파일(`vercel.json`,
`_redirects` 등)로 쉽게 지원하기 때문이다. `HashRouter`는 이 프로젝트처럼 "서버 설정을 만질
권한/방법이 제한적인 환경"이나, GitHub Pages처럼 애초에 커스텀 서버 설정을 지원하지 않는
정적 호스팅에 배포할 때 실무에서도 여전히 쓰이는 실용적인 대안이다.

## 같이 보기

- [React](./React.md) — React Router가 얹히는 기반 라이브러리
- [자체 호스팅(NAS) vs 클라우드](../Infrastructure/Self-Hosting-vs-Cloud.md) — 이 라우팅 제약이 발생한 근본
  원인(관리 콘솔의 한계)

## 참고자료

- [React Router 공식 문서](https://reactrouter.com/)
- `DevelopPrompt/CurrentProject/_RottenNobleProject/CODE_MEMO.md`의 `MEMO-WEB-05`

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | `MEMO-WEB-05`의 HashRouter 결정을 독립 주제로 정리 |
