# StudyProject 문서를 NAS와 동기화하는 GitHub Actions

---

- **카테고리**: 인프라, DevOps, GitHub Actions
- **상태**: 학습 중
- **기준 시점**: 2026-09-15
- **관련 레포지토리**: `StudyProject`, `RottenNoble-Project`
- **엔진**: `Web`
- **상위 문서**: `ComputerScience/Infrastructure/GitHub-Actions.md`

---

## 출처

- `StudyProject/.github/workflows/sync-nas-study.yml`
- `RottenNoble-Project/backend-spring/deploy.sh`
- [GitHub self-hosted runner 등록](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)

## 정의

StudyProject는 학습 문서의 Git 원본이고, RottenNoble 블로그는 NAS의 `/volume1/docker/StudyProject` checkout을 read-only volume으로 mount해 Markdown을 읽는다. 따라서 블로그 코드 배포와 문서 동기화는 별개의 작업이다.

`sync-nas-study.yml`은 StudyProject `main`의 `ComputerScience/**` 변경을 계기로 NAS checkout을 `origin/main`까지 fast-forward한다. 블로그 컨테이너를 재빌드하거나 재시작하지 않는다. 현재 백엔드가 파일을 캐시하지 않는 구조라면 checkout 반영 뒤 다음 API 요청부터 새 문서를 제공한다.

## 요약

| workflow | 저장소 | 트리거 | 책임 |
|---|---|---|---|
| `deploy.yml` | RottenNoble-Project | `develop` push | 프런트·백엔드 빌드와 서비스 배포 |
| `sync-nas-study.yml` | StudyProject | `main`의 `ComputerScience/**` push 또는 수동 실행 | NAS 문서 checkout 갱신 |

ECS 문서를 StudyProject에 push했다고 RottenNoble Actions에 ECS 커밋이 나타나지 않는 것은 정상이다. 문서 동기화 기록은 StudyProject Actions에 남는다.

## 상세

### 데이터 흐름

```text
StudyProject origin/main
  -> StudyProject self-hosted runner
  -> /volume1/docker/StudyProject git fetch + merge --ff-only
  -> RottenNoble backend volume mount read-only
  -> /api/study Markdown 응답
```

RottenNoble의 `deploy.sh`는 NAS checkout을 컨테이너의 `/data/study-project:ro`로 mount한다. 블로그 컨테이너는 문서를 변경할 수 없고, 동기화 runner만 checkout을 갱신할 수 있어야 한다.

### StudyProject 전용 runner가 필요한 이유

RottenNoble 배포 runner는 RottenNoble-Project에 등록된 repository-scoped runner다. 같은 `nas` 라벨을 써도 다른 개인 저장소의 workflow는 그 runner를 사용할 수 없다. 그래서 StudyProject 실행 `34946912643`은 `self-hosted, nas` runner를 찾지 못해 queued 상태가 됐다.

기존 배포 runner를 건드리지 않고 NAS에 두 번째 Docker runner를 만든다. 이 runner는 StudyProject에만 등록하고, StudyProject checkout과 자기 registration/work 경로만 mount한다.

### Synology NAS에서 등록하는 두 번째 runner

GitHub에서 `StudyProject → Settings → Actions → Runners → New self-hosted runner → Linux → x64`로 1시간짜리 등록 토큰을 만든다. NAS SSH에서 `/volume1/docker/StudyProject`을 소유한 계정으로 실행한다.

```sh
sudo docker run -d \
  --name gha-study-runner \
  --restart unless-stopped \
  -e REPO_URL=https://github.com/noble-shake/StudyProject \
  -e RUNNER_TOKEN=<GitHub에서_발급한_1회용_토큰> \
  -e RUNNER_NAME=studyproject-nas-runner \
  -e LABELS=nas \
  -e RUNNER_WORKDIR=/_work \
  -e CONFIGURED_ACTIONS_RUNNER_FILES_DIR=/registration \
  -e DISABLE_AUTOMATIC_DEREGISTRATION=true \
  -v /volume1/docker/gha-study-runner/registration:/registration \
  -v /volume1/docker/gha-study-runner/work:/_work \
  -v /volume1/docker/StudyProject:/volume1/docker/StudyProject \
  myoung34/github-runner:latest
```

이 runner에는 `docker.sock`, 블로그 배포 SSH 개인키, RottenNoble 배포 디렉터리를 mount하지 않는다. 문서 sync에 필요한 권한은 StudyProject checkout write 권한뿐이다. `DISABLE_AUTOMATIC_DEREGISTRATION=true`는 컨테이너 재시작 때 GitHub 등록과 로컬 registration 파일이 어긋나는 문제를 피하기 위한 기존 NAS runner 설정이다.

### workflow의 안전 경계

```yaml
study_dir=/volume1/docker/StudyProject
test -d "$study_dir/.git"
test "$(git -C "$study_dir" branch --show-current)" = "main"
git -C "$study_dir" fetch --quiet origin main
git -C "$study_dir" merge --ff-only origin/main
```

`merge --ff-only`는 NAS의 로컬 수정이나 충돌을 덮어쓰지 않는다. checkout이 수정돼 fast-forward할 수 없으면 job을 실패시킨다. 마지막 smoke check는 TD_Project ECS 문서가 실제 NAS checkout에 있는지 확인한다.

### Git 인증은 runner 등록과 별개다

runner 등록 토큰은 workflow를 받기 위한 용도이지 NAS의 `git fetch` 인증을 대신하지 않는다. NAS checkout이 private StudyProject를 읽을 권한을 가져야 한다.

```sh
git -C /volume1/docker/StudyProject fetch origin main
git -C /volume1/docker/StudyProject status --short --branch
```

인증 오류가 나면 checkout remote에 읽기 전용 PAT 또는 SSH deploy key를 설정한다. token을 workflow YAML이나 로그에 넣지 않는다.

### 장애 진단

| 증상 | 먼저 확인할 것 | 일반적인 원인 |
|---|---|---|
| Actions가 queued | StudyProject Runners | 다른 repo에만 등록됨, offline, `nas` 라벨 없음 |
| runner online인데 실패 | Actions step log | path mount 누락, checkout 권한 문제 |
| `git fetch` 인증 실패 | NAS에서 직접 fetch | remote 인증 만료 또는 미설정 |
| job 성공인데 블로그가 예전 문서 | NAS HEAD, mount, `/api/study` | 다른 checkout, cache, 잘못된 경로 |
| 목록에서 문서가 없음 | metadata와 backend filter | `.flow.md`는 의도적으로 제외 |

```sh
sudo docker ps --filter name=gha-study-runner
sudo docker logs gha-study-runner --tail 50
git -C /volume1/docker/StudyProject log -1 --oneline
```

## 비교표

| 방식 | 장점 | 단점 |
|---|---|---|
| RottenNoble workflow에서 StudyProject pull | runner 하나만 사용 | 문서 push와 서비스 배포 책임이 섞임 |
| NAS cron으로 git pull | GitHub runner 불필요 | 반영 지연, 로그와 수동 실행 UX가 약함 |
| StudyProject 전용 workflow와 runner | 이벤트·로그·수동 실행이 명확 | runner 컨테이너 하나 추가 관리 |

## 질문

- **Q. 블로그를 다시 배포해야 새 문서가 보이나?**
  A. 현재는 NAS checkout을 volume으로 읽으므로 문서 sync만 성공하면 된다. 블로그 코드·파서·UI를 바꿀 때만 RottenNoble 배포가 필요하다.

- **Q. `DOCS_BUNDLE.html`만 바뀌어도 자동 sync되나?**
  A. 현재 trigger는 `ComputerScience/**`다. 실제 블로그가 읽는 Markdown에만 반응하도록 제한했다. bundle이나 root README만 변경한 경우에는 Actions에서 수동 실행한다.

- **Q. 기존 runner에 StudyProject를 같이 등록할 수 있나?**
  A. 현재는 repository-scoped runner이므로 별도 runner 컨테이너를 권장한다. 개인 저장소 두 개에는 이 구성이 단순하고 권한 경계도 명확하다.

## 실무

- `--ff-only`를 유지해 NAS 로컬 변경을 보호한다.
- runner는 repository 하나와 필요한 volume만 받도록 최소 권한으로 둔다.
- 문서 API에 cache를 추가하면 checkout 갱신 뒤 cache invalidation 정책도 같이 설계한다.
- Actions 성공은 runner 명령 성공이다. NAS HEAD와 실제 `/api/study` 응답으로 서비스 반영까지 확인한다.

## 같이 보기

- [GitHub Actions](./GitHub-Actions.md)
- [Self-hosting과 Cloud](./Self-Hosting-vs-Cloud.md)
- [TD_Project ECS Warm-up](../Architecture/TD_Project-ECS-Warmup.md)

## 참고자료

- [GitHub Adding self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners)
- [GitHub Using labels with self-hosted runners](https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/apply-labels)
- [GitHub Choosing a runner](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
- [myoung34 docker GitHub Actions runner](https://github.com/myoung34/docker-github-actions-runner)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-15 | 최초 작성 | ECS 문서가 NAS checkout에 반영되지 않은 원인을 분리하고 자동 동기화 workflow를 추가 |

