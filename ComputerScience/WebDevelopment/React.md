# React

---

- **카테고리**: 웹 개발, 프런트엔드
- **상태**: 완료
- **기준 시점**: 2026-09-08, React 19 기준
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNobleProject` — `RottenNobleProject-Architecture.md` 1~3회차 코드 학습에서 나온 주제.

## 정의

React는 사용자 인터페이스(UI)를 **컴포넌트** 단위로 만드는 자바스크립트 라이브러리다. 컴포넌트란
"화면의 한 조각을 만드는 함수"라고 생각하면 된다 — 데이터(props나 상태)를 받아서, 그 데이터에
맞는 화면 구조(JSX)를 반환한다. 데이터가 바뀌면 React가 알아서 화면의 필요한 부분만 다시
그려준다.

## 요약

이 프로젝트는 페이지마다 컴포넌트를 하나씩 두고(`PostList`, `PostEditor` 등), 각 컴포넌트가
`useState`로 자기 상태를 관리하고 `useEffect`로 API를 호출하는, React의 가장 기본적이고 표준적인
패턴만으로 이루어져 있다 — Redux 같은 전역 상태 관리 라이브러리도, 복잡한 커스텀 훅 체계도 없다.

## 상세

### 컴포넌트와 JSX

```jsx
// frontend/src/pages/Login/Login.jsx의 일부
function Login() {
  const [username, setUsername] = useState('');
  // ...
  return (
    <div className="page page-narrow">
      <h1>관리자 로그인</h1>
      <form onSubmit={handleSubmit}>
        {/* ... */}
      </form>
    </div>
  );
}
```

`function Login() { ... }`이 컴포넌트다. 함수 안의 `return`문에 있는 것처럼 생긴 HTML 비슷한
코드가 **JSX**인데, 이건 실제 HTML이 아니라 자바스크립트 문법의 확장이다 — 빌드 도구(이
프로젝트에서는 CRA/Webpack)가 이걸 `React.createElement(...)` 호출로 변환한다. JSX 안에서
`{}`로 감싼 부분은 순수 자바스크립트 표현식이라는 게 핵심 규칙이다.

### `useState` — 컴포넌트가 스스로 기억하는 값

```jsx
// frontend/src/pages/PostEditor/PostEditor.jsx
const [title, setTitle] = useState('');
```

`useState('')`는 "초깃값이 빈 문자열인 상태 하나"를 만든다. `title`은 지금 값을, `setTitle`은
그 값을 바꾸는 함수다. **핵심은 `setTitle`을 호출하면 React가 이 컴포넌트를 다시 실행해서 화면을
새로 그린다**는 것 — 일반 변수를 바꾸는 것과 근본적으로 다르다. 일반 변수(`let title = ''`)를
바꾸면 화면엔 아무 변화도 안 생긴다. React가 "이 값이 바뀌면 화면을 다시 그려야 한다"는 걸 알
수 있는 유일한 방법이 `useState`가 제공하는 setter 함수이기 때문이다.

### `useEffect` — 컴포넌트가 화면에 나타난 뒤에 할 일

```jsx
// frontend/src/pages/PostEditor/PostEditor.jsx
useEffect(() => {
  if (!isEdit) return;
  fetchPost(id)
    .then((post) => { setTitle(post.title); setContent(post.content); })
    .catch((err) => setError(err.message))
    .finally(() => setLoading(false));
}, [id, isEdit]);
```

컴포넌트 함수 자체(위의 JSX를 반환하는 부분)는 "지금 이 데이터로 화면이 어떻게 생겨야 하는가"만
설명해야 하고, API 호출 같은 **부수 효과(side effect)**는 별도로 다뤄야 한다는 게 React의
설계다. `useEffect`가 그 자리다 — 두 번째 인자인 배열(`[id, isEdit]`, "의존성 배열")에 적힌
값이 바뀔 때만 이 함수를 다시 실행한다. 이 프로젝트는 "수정 모드(`isEdit`)일 때만, `id`가 바뀔
때마다 그 글을 다시 불러온다"는 걸 이 한 줄로 표현하고 있다.

### 이 프로젝트가 안 쓰는 것들

React 생태계에는 이 프로젝트가 쓰지 않은 것들이 많다:

- **전역 상태 관리(Redux, Zustand, Context API)** — `Login.jsx`의 주석을 보면 로그인 성공 후
  `navigate()` 대신 `window.location.href = '/'`로 전체 새로고침을 쓰는데, 그 이유가 바로 "Nav의
  로그인 상태를 새로고침 없이 갱신하려면 전역 상태가 필요한데, 이 규모엔 과하다"는 판단이다. 즉
  안 쓴 게 아니라, 안 써도 되는 방법으로 우회한 것이다.
- **TypeScript** — `.jsx` 확장자를 쓰고 있어 타입 검사가 없다. props나 상태 값의 타입은 코드를
  직접 읽어야 알 수 있다.
- **커스텀 훅** — `useState`/`useEffect`를 여러 컴포넌트에서 비슷하게 반복해서 쓰고 있지만
  (`error`/`submitting` 상태 패턴이 `Login.jsx`와 `PostEditor.jsx`에서 거의 동일하다), 이걸
  `useAsyncForm()` 같은 커스텀 훅으로 뽑아내지는 않았다 — 페이지가 5개뿐인 지금 규모에서는 중복이
  아직 리팩터링을 정당화할 만큼 크지 않다고 볼 수 있다.

## 비교표

| 개념 | 역할 | 이 프로젝트에서 쓰인 곳 |
|---|---|---|
| 컴포넌트(함수) | 화면 조각 하나를 만든다 | `pages/*/**.jsx` 각각 |
| `useState` | 컴포넌트가 스스로 값을 기억하고, 바뀌면 다시 그린다 | 폼 입력값, `loading`/`error`/`submitting` 상태 |
| `useEffect` | 화면에 나타난 뒤(또는 특정 값이 바뀐 뒤) 할 일 | `PostEditor`가 수정 모드일 때 글 데이터 불러오기 |
| `useNavigate`/`useParams` (react-router) | 페이지 이동, URL 파라미터 읽기 | 글 저장 후 상세 페이지로 이동, `:id` 읽기 |

## 질문

- **Q. `useEffect`의 의존성 배열을 빠뜨리면 어떻게 되나?**
  A. React는 컴파일 타임에 이걸 강제로 막지는 않지만(ESLint 규칙이 경고는 해준다), 실제로
  빠뜨리면 그 값이 바뀌어도 effect가 다시 실행되지 않아서 화면이 오래된 데이터를 계속 보여주는
  버그가 생긴다. `PostEditor.jsx`가 `[id, isEdit]`을 정확히 넣어둔 건, `/posts/1/edit`에서
  `/posts/2/edit`으로 바로 이동했을 때도(컴포넌트가 언마운트되지 않고 재사용될 수 있음) 새
  `id`로 다시 데이터를 불러오게 하기 위함이다.

- **Q. React 19는 이전 버전과 뭐가 다른가?**
  A. React 19는 `use()` 훅, 폼 관련 새 훅(`useActionState`, `useFormStatus`) 등 서버 연동을
  더 매끄럽게 하는 기능들을 추가했다. 다만 이 프로젝트는 이런 신규 기능을 쓰지 않고
  `useState`/`useEffect` 같은 이전부터 있던 기본 훅만으로 구성돼 있다 — 최신 버전을 쓰고 있지만
  실제로는 오래전부터 안정적으로 쓰이던 패턴만 활용하고 있는 셈이다.

## 예시 코드

```jsx
// frontend/src/pages/PostList/PostList.jsx 패턴 요약 — 목록을 불러와 렌더링하는 전형적인 형태
function PostList() {
  const [posts, setPosts] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchPosts()
      .then(setPosts)
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <p>불러오는 중…</p>;
  return (
    <ul>
      {posts.map((post) => <li key={post.id}>{post.title}</li>)}
    </ul>
  );
}
```

`useEffect`의 의존성 배열이 빈 배열(`[]`)이면 "컴포넌트가 처음 화면에 나타날 때 딱 한 번만
실행"이라는 뜻이다 — 목록을 한 번만 불러오면 되는 이런 경우의 표준 패턴이다.

## 플로우차트

(생략 — 컴포넌트/훅 개념은 "무엇이 무엇을 트리거하는가"보다 "각 개념이 무슨 역할인가"가 핵심이라
표로 이미 충분히 정리된다.)

## 실무

React는 현재 프런트엔드 라이브러리 중 가장 널리 쓰이는 선택지 중 하나이고, 실무에서는 이
프로젝트처럼 순수 `useState`/`useEffect`만 쓰기보다 상태 관리 라이브러리(Redux Toolkit,
Zustand, TanStack Query 등)를 함께 쓰는 경우가 많다 — 특히 서버 데이터를 다루는 부분은
TanStack Query 같은 라이브러리가 로딩/에러/캐싱 상태 관리를 대신해줘서, 이 프로젝트가 각
페이지마다 손으로 반복하고 있는 `loading`/`error` 상태 패턴을 크게 줄여준다. 다만 이 프로젝트
규모(페이지 5개)에서는 그런 라이브러리 없이도 코드가 아직 읽기 어렵지 않다 — "언제부터 상태
관리 라이브러리가 필요해지는가"를 실감하기에 좋은 기준점이 되는 프로젝트다.

## 같이 보기

- [React Router](./React-Router.md) — 이 프로젝트가 페이지 간 이동을 처리하는 방식
- [CRA → Vite 마이그레이션](./CRA-vs-Vite.md) — React 자체가 아니라 이를 감싼 빌드 도구의 문제
- [Token Storage](../Security/Token-Storage.md) — `isLoggedIn()`처럼 React 바깥(localStorage) 상태를
  컴포넌트 상태와 동기화하는 방식

## 참고자료

- [React 공식 문서](https://ko.react.dev/)
- [React 공식 문서 — useEffect](https://ko.react.dev/reference/react/useEffect)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-08 | 최초 작성 | 1~3회차 학습에서 반복 확인한 프런트엔드 패턴을 독립 주제로 정리 |
