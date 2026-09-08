# VIEWER — md 문서 뷰어

`DevelopPrompt/VIEWER`의 엔진을 그대로 재사용한 것이다 — 다른 점은 `index.html`의 사이드바
그룹핑을 `ComputerScience/{분야}/` 카테고리 트리에 맞춰 바꾼 것뿐이다.

## 파일

| 파일 | 용도 |
|---|---|
| `index.html` | 뷰어 엔진(렌더러) 템플릿. `build_bundle.ps1`이 이 파일을 바탕으로 저장소 루트의 `DOCS_BUNDLE.html`을 만든다 |
| `build_bundle.ps1` | `-Root <폴더>`의 md를 전부 모아 `<폴더>/DOCS_BUNDLE.html`(또는 `-Output`으로 지정한 경로)을 생성 |
| `build_bundle.cmd` | 위 스크립트의 인자 없는 런처(직접 쓰기보다 저장소 루트의 `build_bundle.cmd`를 쓰는 걸 권장) |
| `mermaid.min.js` | 다이어그램 렌더링 엔진. 로컬 파일이라 오프라인에서도 동작한다 |

## 쓰는 법

**번들 만들기/갱신하기** — 저장소 루트의 [`build_bundle.cmd`](../build_bundle.cmd)를 더블클릭하면
`ComputerScience/` 아래 전체(하위 폴더 재귀 포함)를 모아 루트에 `DOCS_BUNDLE.html`을 만든다.

**그냥 읽기** → 루트의 `DOCS_BUNDLE.html` 더블클릭

**수정 직후 미리보기** → `VIEWER/index.html`을 열고 고친 md 파일들을 창에 끌어다 놓으면 번들을
새로 만들지 않고도 바로 확인 가능

## 알아둘 것

- 이 뷰어는 md 원본을 그대로 렌더링한다. **내용 수정은 항상 md 파일에서** 하고, 고친 뒤에는
  `build_bundle.cmd`를 다시 실행해야 `DOCS_BUNDLE.html`에 반영된다 — HTML은 파생물이다.
- `.flow.md` 별첨 파일은 사이드바에 따로 안 뜬다(본문 안 링크로만 이동) — 목록이 플로우차트로
  도배되지 않게 하기 위함.
- `file://`로 열면 브라우저 보안 정책상 md를 자동으로 못 읽는다. 그래서 **번들(내장) 방식**과
  **파일 선택/드래그** 두 경로를 둔 것이다.
- 지원 문법: 제목 · 목록 · 체크박스 · 표 · 코드펜스 · 인용 · 링크 · 강조 · 인라인 코드 · mermaid 블록.
