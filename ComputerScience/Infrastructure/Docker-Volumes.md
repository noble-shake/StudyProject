# Docker 볼륨 — 컨테이너를 지워도 살아남아야 하는 데이터 분리하기

---

- **카테고리**: 인프라, DevOps
- **상태**: 완료
- **기준 시점**: 2026-09-29
- **관련 레포지토리**: `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: -

---

## 출처

`RottenNoble-Project`의 글 작성 에디터에 이미지 업로드 기능을 추가하면서, 업로드된 파일을
어디에 저장할지 결정해야 했다(`RottenNoble-Project` `Study.md` 관련 항목). 이 프로젝트의 배포
파이프라인(`GitHub-Actions.md` 참고)은 `develop`에 push될 때마다 백엔드 컨테이너를
`docker rm -f` 후 새로 `docker run`한다 — 즉 컨테이너 자체는 매 배포마다 완전히 새로 만들어지는
일회용품이다. 이 사실을 놓치고 컨테이너 내부 파일시스템에 업로드 파일을 저장했다면, 다음 배포
순간 전부 사라졌을 것이다.

## 정의

Docker 컨테이너의 파일시스템은 기본적으로 컨테이너 자신의 생애주기를 따른다 — 컨테이너를
`docker rm`으로 지우면 그 안에 쓴 파일도 함께 사라진다. **볼륨(volume)** 또는 **바인드 마운트
(bind mount)**는 컨테이너 바깥(호스트 파일시스템 또는 Docker가 관리하는 별도 저장 영역)에 있는
디렉토리를 컨테이너 안의 특정 경로에 연결해서, 컨테이너가 지워지고 다시 만들어져도 그 경로의
내용은 호스트에 그대로 남아있게 만드는 방법이다. `docker run -v <호스트 경로>:<컨테이너 경로>`
형태로 지정한다(바인드 마운트 — 호스트의 실제 경로를 지정). Docker가 자체 관리하는 이름 붙은
볼륨(`docker volume create`)도 있지만, 이 프로젝트는 사람이 직접 NAS 경로를 들여다보거나 백업할
일이 많아서 바인드 마운트만 쓴다.

## 요약

**컨테이너 수명과 데이터 수명은 다르다.** "이 컨테이너가 재시작/재생성돼도 남아있어야 하는가?"가
"예"인 데이터는 전부 볼륨으로 빼야 한다. 이 프로젝트는 이미 `StudyProject`(이 문서 저장소
자체의 git 체크아웃, 읽기전용)와 `GeoIP` DB 파일(선택, 읽기전용)을 이 패턴으로 마운트하고
있었고, 이번에 업로드 이미지 저장용 `uploads` 디렉토리를 읽기-쓰기로 추가했다.

## 상세

### 왜 이미지가 처음부터 볼륨 후보였나

새 기능(이미지 업로드)을 설계할 때 자문해야 할 질문은 "이 데이터가 다음 배포에도 살아있어야
하는가"다. 블로그 글 본문에 끼워 넣는 이미지는 당연히 다음 배포 때 사라지면 안 된다 — 그렇다면
설계 시점부터 컨테이너 내부 경로가 아니라 볼륨 경로에 저장하도록 정해야 한다. 이미 기존
`StudyProject`/`GeoIP` 마운트가 있었으므로, 같은 패턴(호스트 디렉토리 → 컨테이너 `/data/*`)을
그대로 따라가면 됐다.

```java
// backend-spring: 저장 위치는 설정값 하나(app.upload.dir)로 받는다.
// 로컬 개발에서는 프로젝트 밖 아무 폴더, NAS에서는 볼륨 마운트 경로(/data/uploads)를 가리킨다 —
// 코드는 "이게 볼륨인지 아닌지" 전혀 모른다. 볼륨 여부는 순전히 배포 스크립트의 -v 플래그가 결정한다.
public UploadController(@Value("${app.upload.dir}") String uploadDir) {
    this.uploadDir = Path.of(uploadDir);
}
```

이 대목이 핵심이다 — **애플리케이션 코드는 자기가 쓰는 디렉토리가 볼륨인지 컨테이너 내부의
일회용 경로인지 알 필요도, 알 방법도 없다.** "영구적이어야 한다"는 결정은 전적으로 배포
스크립트(`docker run -v ...`)의 책임이다. 코드는 그냥 설정된 경로에 파일을 쓸 뿐이고, 그 경로가
실제로 영구적인지는 인프라 쪽에서 보장해야 한다 — 이 분리가 안 되면(예: 코드에 경로를
하드코딩) 나중에 배포 방식이 바뀔 때 코드까지 같이 고쳐야 한다.

### 기존 마운트와 새 마운트의 차이 — git clone vs 빈 폴더

```sh
# 기존: StudyProject — 사람이 미리 git clone 해둬야 하는 저장소. 없으면 실패시켜야 한다
# (없는데 그냥 진행하면 Study 메뉴가 원인 모르게 빈 화면이 된다).
STUDY_PROJECT_DIR="${STUDY_PROJECT_DIR:-/volume1/docker/StudyProject}"
if [ ! -d "$STUDY_PROJECT_DIR" ]; then
  echo "$STUDY_PROJECT_DIR 가 없습니다 — StudyProject를 여기에 clone 해두세요:"
  exit 1
fi

# 신규: uploads — 그냥 빈 디렉토리라 사람이 미리 준비할 이유가 없다. 없으면 실패시키지 않고
# 그 자리에서 만든다.
UPLOADS_DIR="${UPLOADS_DIR:-/volume1/docker/rottennoble-backend/uploads}"
mkdir -p "$UPLOADS_DIR"
```

같은 "영구 디렉토리 마운트" 패턴이어도, **디렉토리의 초기 상태를 사람이 준비해야 하는가**에
따라 배포 스크립트의 대응이 달라야 한다. `StudyProject`는 특정 git 저장소의 내용이 반드시
있어야 의미가 있으므로 없으면 배포를 막고 사람에게 알린다. `uploads`는 애초에 빈 폴더로
시작해도 전혀 문제가 없으므로(첫 업로드 전까지는 비어있는 게 정상 상태) `mkdir -p`로 조용히
만들고 넘어간다. "영구 마운트가 필요하다"는 결론만 같고 "실패 조건"은 다르다 — 이 구분을
안 하면 uploads 하나 때문에 배포가 막히거나, 반대로 StudyProject가 없는데도 조용히 넘어가서
나중에야 문제를 발견하게 된다.

### 왜 애플리케이션 컨텍스트 시작 시점에 디렉토리를 만들면 안 되는가

처음 구현에서는 `UploadController`의 생성자(스프링 빈 초기화 시점)에서
`Files.createDirectories(uploadDir)`를 호출했다. 문제는 스프링 빈 생성 중 예외가 나면 **애플리케이션
컨텍스트 전체가 뜨지 않는다** — 업로드 디렉토리 하나에 권한 문제가 생겨도, 그 기능과 전혀 상관없는
게시글 목록·방명록·사진첩 API까지 전부 502가 난다. 그래서 디렉토리 생성을 실제 업로드 요청이
들어왔을 때(컨트롤러 메서드 안)로 옮겼다 — 이러면 uploads 관련 문제가 생겨도 그 요청 하나만
실패하고 나머지 사이트는 정상 동작한다.

> **핵심 교훈**: 특정 기능 하나의 초기화 실패가 애플리케이션 전체를 끌고 내려가지 않게, "이
> 자원이 꼭 필요한 시점"까지 초기화를 늦추는 것도 blast radius를 좁히는 방법이다. Redis 연결
> 실패 시 rate limiting만 통과시키고 사이트는 계속 동작하게 만든 것([Rate-Limiting](../Security/Rate-Limiting.md))과
> 같은 원칙이다 — 다만 여기서는 "장애 시 계속 동작"이 아니라 "초기화 시점 자체를 늦춰서
> 실패 범위를 좁히는" 변형이다.

## 비교표

| 저장 방식 | 배포(컨테이너 재생성) 후 유지 | 이 프로젝트에서 쓴 곳 |
|---|---|---|
| 컨테이너 내부 파일시스템(마운트 없음) | 유지 안 됨 | 로그 등 일회성 데이터만(현재 없음) |
| 바인드 마운트(호스트 디렉토리 직접 지정) | 유지됨 | `StudyProject`(읽기전용, git clone), `GeoIP`(읽기전용, 선택), `uploads`(읽기-쓰기, 이번에 추가) |
| Docker 관리 볼륨(`docker volume create`) | 유지됨 | 안 씀 — 호스트 경로를 직접 봐야 할 일이 많아 바인드 마운트가 더 편함 |
| DB(MariaDB) | 유지됨(DB 자체가 영구 저장소) | 게시글·방명록·사진첩 메타데이터. 실제 이미지 파일은 DB에 안 넣고 경로만 저장 |

## 질문

- **Q. 이미지 파일 자체를 DB에 BLOB으로 저장하는 방법도 있지 않나?**
  A. 가능은 하지만 이 프로젝트에서는 안 썼다 — DB 백업 용량이 커지고, 정적 파일 서빙을
  DB 조회를 거쳐서 해야 해서 성능상 불리하다. 파일은 볼륨(파일시스템)에 두고 DB에는 경로/URL만
  저장하는 쪽이 일반적이고, 이 프로젝트도 그 방식을 따랐다(`gallery_photos.image_url`,
  게시글 본문의 마크다운 이미지 링크).

- **Q. `mkdir -p`로 조용히 만드는 게 항상 맞나? StudyProject처럼 실패시켜야 할 때도 있지 않나?**
  A. 위 "상세"에서 다룬 것처럼 기준은 "이 디렉토리가 특정 내용을 미리 갖추고 있어야 의미가
  있는가"다. 내용이 없어도 빈 상태로 시작하는 게 정상인 데이터(업로드 파일 저장소, 캐시 등)는
  조용히 만들면 되고, 특정 선행 작업(git clone, 라이선스 파일 다운로드 등)이 필요한 데이터는
  없을 때 배포를 막고 사람에게 알려야 한다 — 안 그러면 "왜 이 기능이 계속 비어있지"를 나중에야
  발견하게 된다.

## 예시 코드

**배포 스크립트의 마운트 추가** (`backend-spring/deploy.sh`):

```sh
UPLOADS_DIR="${UPLOADS_DIR:-/volume1/docker/rottennoble-backend/uploads}"
mkdir -p "$UPLOADS_DIR"

docker run -d --name rottennoble-backend \
  --restart unless-stopped \
  -p 8080:8080 \
  --env-file .env.prod \
  -v "$STUDY_PROJECT_DIR:/data/study-project:ro" \
  -v "$UPLOADS_DIR:/data/uploads" \
  rottennoble-backend
```

**정적 파일 서빙 연결** (`WebConfig.java`) — 마운트된 디렉토리를 HTTP로 그대로 내려준다:

```java
@Override
public void addResourceHandlers(ResourceHandlerRegistry registry) {
    String location = uploadDir.endsWith("/") ? uploadDir : uploadDir + "/";
    registry.addResourceHandler("/uploads/**").addResourceLocations("file:" + location);
}
```

### 확인 예시

재배포 전후로 실제 업로드 파일 하나를 curl로 확인하면 볼륨이 제대로 물려있는지 검증할 수 있다:

```bash
# 재배포 전
curl -sI https://api.rotten-noble.com/uploads/<파일명>.jpg   # 200 확인

# develop에 아무 커밋이나 push해서 재배포 트리거 → 컨테이너가 rm -f 후 새로 만들어짐

# 재배포 후 — 볼륨이 없었다면 여기서 404가 난다
curl -sI https://api.rotten-noble.com/uploads/<파일명>.jpg   # 여전히 200이어야 정상
```

## 플로우차트

없음 — 개념 자체가 "마운트 있음/없음"의 단순 이분법이라 별도 그림 없이 위 비교표로 충분하다고
판단(`00_VISUALIZING_POLICY.md` §1 기준).

## 실무

실무에서는 이 정도 규모(파일 수 적음, NAS 한 대)를 넘어서면 로컬 볼륨 대신 S3 같은 오브젝트
스토리지로 옮기는 경우가 많다 — 여러 서버 인스턴스가 같은 파일에 접근해야 하거나(로컬 볼륨은
그 호스트에만 존재), CDN을 앞에 붙이고 싶을 때 특히 그렇다. 이 프로젝트가 로컬 볼륨을 쓰는
이유는 순전히 규모(개인 블로그, 서버 한 대) 때문이지 원칙적으로 더 나은 방법이라서가 아니다 —
서버를 여러 대로 늘리거나 트래픽이 커지면 이 선택부터 재검토해야 한다.

## 같이 보기

- [Self-Hosting-vs-Cloud](Self-Hosting-vs-Cloud.md) — 애초에 자체 NAS를 서버로 쓰기로 한 배경
- [GitHub-Actions](GitHub-Actions.md) — 이 볼륨이 왜 필요한지의 전제가 되는 배포 파이프라인(매 배포마다 컨테이너 재생성)
- [Rate-Limiting](../Security/Rate-Limiting.md) — "장애 시 전체가 죽지 않게 범위를 좁힌다"는 같은 원칙의 다른 사례

## 참고자료

- [Docker docs — Volumes](https://docs.docker.com/engine/storage/volumes/)
- [Docker docs — Bind mounts](https://docs.docker.com/engine/storage/bind-mounts/)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-29 | 최초 작성 | `RottenNoble-Project`에 이미지 업로드 기능을 추가하며 실제로 겪은 볼륨 설계(빈 폴더 vs git clone 마운트의 실패 조건 차이, 생성자에서 디렉토리를 만들면 안 되는 이유)를 정리 |
