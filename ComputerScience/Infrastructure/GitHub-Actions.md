# GitHub Actions — push 한 번으로 빌드부터 배포까지 자동화하기

---

- **카테고리**: 인프라, DevOps
- **상태**: 완료
- **기준 시점**: 2026-09-10
- **관련 레포지토리**: `RottenNoble-Project`

---

## 출처

`RottenNoble-Project`를 Spring Boot + Vite로 재작성한 뒤, 배포 과정이 "로컬에서 빌드 →
NAS로 scp → NAS에 SSH 접속해서 `sudo sh deploy.sh` 실행"이라는 완전 수동 절차였다. 실제로
겪어보니 매번 4~5개 명령을 순서대로 치는 것도 번거로웠고, 그 와중에 Windows에서 체크아웃한
셸 스크립트가 CRLF로 저장되어 NAS의 `sh`가 못 읽는 사고까지 겹쳤다. "모바일이나 사무실에서도
배포하고 싶다"는 요구가 나오면서, `develop` 브랜치에 push만 하면 끝나도록 GitHub Actions로
자동화했다. 이 문서는 그 과정에서 실제로 부딪힌 문제들(오래된 NAS의 glibc, 컨테이너 재시작
버그, 셸 환경 차이)과 그걸 어떻게 풀었는지를 정리한 것이다.

## 정의

GitHub Actions는 저장소에서 특정 이벤트(push, PR, 수동 트리거 등)가 발생하면 미리 정의해둔
작업(workflow)을 자동으로 실행해주는 GitHub 내장 CI/CD 도구다. workflow는 `.github/workflows/`
아래 YAML 파일로 정의하고, 실제 작업은 **러너(runner)**라는 머신에서 실행된다. 러너는 두 종류다:

- **GitHub-hosted 러너**: GitHub가 매 작업마다 새로 띄워주는 임시 가상머신. 관리가 필요 없지만,
  이 러너에서는 우리 집 NAS 안쪽(사설 IP `192.168.50.2`)에 있는 배포 대상에 직접 파일을 쓸 수
  없다 — 결국 SSH/scp로 다시 접속해야 하니 자동화의 이점이 줄어든다.
- **Self-hosted 러너**: 우리가 직접 준비한 머신에 러너 프로그램을 설치해서 등록하는 방식. 이
  러너가 NAS 자신이라면, 빌드 산출물을 scp 없이 `cp`로 바로 배포 대상 경로에 넣을 수 있다.

## 요약

이 프로젝트는 self-hosted 러너를 NAS 위 Docker 컨테이너에 띄우는 방식을 택했다. `develop`
브랜치에 push가 들어오면 러너가 체크아웃 → 프런트(Vite) 빌드 → 정적 파일을 Web Station
경로에 `cp` → 백엔드(Spring Boot) 빌드 → jar를 배포 디렉토리에 `cp` → **호스트로 SSH
콜백해서 `sudo sh deploy.sh` 한 줄만 실행**해서 Docker 컨테이너를 재기동한다. 마지막 단계를
컨테이너 내부의 `docker.sock` 마운트가 아니라 SSH 콜백으로 뺀 게 이 설계의 핵심 — 이유는
[상세](#왜-dockersock을-마운트하지-않았나) 참고.

## 상세

### 왜 self-hosted 러너를 골랐나

GitHub-hosted 러너를 썼다면 매 작업마다 SSH 키를 GitHub Secrets에 등록하고, scp로 파일을
옮기고, 원격으로 `sudo` 명령을 실행하는 구조가 필요했다 — 지금 손으로 하던 걸 그대로
스크립트로 옮기는 것뿐이라 번거로움이 크게 줄지 않는다. 반면 러너를 NAS 자신 위에 두면
"배포"가 단순히 "같은 파일시스템 안에서 파일 복사"가 되어 scp도, 대부분의 SSH 키 관리도
필요 없어진다. 대가는 러너를 직접 설치·유지보수해야 한다는 것 — 이 프로젝트처럼 이미 NAS가
있는 [자체 호스팅](Self-Hosting-vs-Cloud.md) 환경이라면 이 대가가 작다.

### 오래된 NAS와 glibc — 가장 크게 부딪힌 문제

이 NAS(Synology DS218+, Apollo Lake)는 `glibc 2.26`이라는 상당히 오래된 C 라이브러리를 쓴다.
GitHub Actions 러너는 내부적으로 Node.js(현재는 node20/node24)를 번들해서 액션(예:
`actions/checkout`, `actions/setup-node`)을 실행하는데, 이 번들 Node.js는 `glibc >= 2.28`을
요구한다. 그 결과 러너를 NAS에 **네이티브로** 설치했을 때 이런 순서로 계속 막혔다:

1. `./config.sh` 실행 자체가 `ldd`, `ldconfig` 명령이 없어서 실패 (임베디드 환경이라 아예
   설치가 안 돼 있었다) → 동적 링커(`ld-linux-x86-64.so.2`)를 직접 감싸는 셸 스크립트로
   대체해서 우회.
2. 러너 서비스가 떠도 실제 작업(`actions/checkout`)의 post-step에서 `GLIBC_2.27' not found`로
   실패 → Alpine용 musl 빌드(`node20_alpine`)는 있었지만 이번엔 musl 런타임 자체가 없어서
   또 실패 → Alpine 패키지에서 `ld-musl-x86_64.so.1`을 직접 추출해 `/lib`에 넣어서 우회.
3. 그렇게 해도 `actions/setup-node`, `actions/setup-java`가 **매번 새로 다운로드하는**
   node/Java 런타임까지 같은 문제를 겪을 게 뻔했다 — 액션 하나하나를 패치하는 건 끝이
   없는 구조적 문제였다.

결론: **패치를 계속 쌓는 대신, 러너 자체를 최신 glibc를 가진 Docker 컨테이너(Ubuntu 기반
`myoung34/github-runner` 이미지) 안에서 돌리는 쪽으로 방향을 바꿨다.** 컨테이너는 호스트의
glibc와 완전히 무관한 자기만의 파일시스템을 가지므로, 호스트가 아무리 오래됐어도 컨테이너
안의 도구들은 항상 최신 버전을 쓸 수 있다.

> **핵심 교훈**: 오래된 시스템에 최신 도구를 "맞춰 넣으려는" 시도는 개별 증상을 하나씩
> 고쳐도 다음 증상이 계속 나온다. 증상이 같은 근본 원인(여기선 glibc 버전)에서 반복해서
> 나온다면, 그 근본 원인 자체를 우회하는 격리 계층(컨테이너)을 쓰는 게 더 적은 노력으로
> 끝난다.

### 왜 docker.sock을 마운트하지 않았나

컨테이너 안의 러너가 NAS의 Docker 데몬에 직접 명령(`docker build`, `docker run`)을 내리는
가장 쉬운 방법은 호스트의 `/var/run/docker.sock`을 컨테이너에 그대로 마운트하는 것이다.
이러면 컨테이너 안에서 `docker` 명령이 호스트의 Docker 데몬을 그대로 조종할 수 있다 — 하지만
이건 사실상 **호스트에 대한 root 권한**과 같다 (Docker 데몬 자체가 root로 동작하고, 임의
컨테이너를 호스트 파일시스템 전체가 마운트된 상태로 띄울 수 있기 때문). 이 NAS는 블로그뿐
아니라 `StylizedActionRPG`의 게임 서버 스택(httpserver/tcpserver/mongodb/redis)도 같은
호스트에서 돌고 있어서, CI 워크플로우 하나가 뚫리면 게임 서버까지 전부 위험해지는 구조가
된다.

그래서 택한 방식은 **최소 권한 SSH 콜백**이다:

1. 컨테이너 안에는 전용 SSH 개인키 하나만 읽기 전용으로 넣는다.
2. 이 키의 공개키를 NAS의 `~/.ssh/authorized_keys`에 등록할 때, `command="..."` 옵션으로
   **딱 한 가지 명령만** 실행하도록 강제한다 (forced command). 이 키로는 그 외 어떤 명령도
   실행할 수 없다 — 워크플로우 코드가 실수로 다른 명령을 보내도 무시된다.
3. 그 명령(`sudo sh deploy.sh`)이 비밀번호 없이 실행되도록, `/etc/sudoers.d/`에 **그 스크립트
   경로 하나만** 허용하는 NOPASSWD 규칙을 추가한다 — `docker` 명령 전체가 아니라 이 스크립트
   실행 권한만 연다.

두 겹(SSH forced command + 범위 제한 sudoers)을 겹쳐서, 이 키가 유출되거나 워크플로우가
악의적으로 수정되더라도 할 수 있는 일은 "이 배포 스크립트를 다시 실행하는 것"뿐이도록 만들었다.

### 컨테이너 재시작 무한 루프 — reusage와 자동 등록해제의 충돌

컨테이너를 처음 띄웠을 때, 첫 등록은 성공("Runner successfully added")하는데 곧바로
`Restarting (1)`을 반복하는 crash loop에 빠졌다. 원인은 이미지(`myoung34/github-runner`)의
기본 동작 두 가지가 서로 충돌한 것이었다:

- **Reusage**(재사용): 컨테이너가 재시작될 때 등록 정보를 로컬 볼륨에 저장해뒀다가 재사용해서,
  매번 새로 등록하지 않게 해주는 기능.
- **자동 등록해제**(기본값 켜짐): 컨테이너가 **어떤 이유로든 종료될 때** GitHub에서 러너 등록을
  스스로 해제하는 기능.

두 기능을 동시에 켜두면: 컨테이너 종료 → 자동 등록해제로 GitHub 쪽 등록은 사라짐 → 로컬
볼륨엔 등록 파일이 그대로 남아있음 → 재시작 시 "이미 설정됨"으로 판단해 재등록을 안 함 →
실제로는 GitHub가 이 러너를 모르는 상태라 리스너가 인증에 실패하고 즉시 종료 → 다시
자동 등록해제 → 무한 반복. `DISABLE_AUTOMATIC_DEREGISTRATION=true` 환경변수로 종료 시
자동 해제를 끄니 바로 해결됐다.

### PATH 문제 — forced command는 로그인 셸이 아니다

SSH forced command로 실행되는 `deploy.sh`가 `docker: command not found`로 실패했다. 평소
터미널에 SSH로 접속하면 `.profile`/`.bashrc`가 로드되면서 `PATH`에 `/usr/local/bin`(NAS의
`docker` 심볼릭 링크 위치)이 들어가지만, forced command는 그런 셸 초기화 없이 지정된 명령을
바로 실행하기 때문에 최소한의 `PATH`만 갖는다. `deploy.sh` 맨 위에 `export PATH="/usr/local/bin:$PATH"`
한 줄을 추가해서 해결했다 — "내 터미널에서는 되는데 스크립트로 실행하면 안 된다"의 전형적인
원인이다.

## 비교표

| 접근 | 결과 | 비고 |
|---|---|---|
| 네이티브 러너 + 개별 glibc 패치 | 실패 | 증상이 계속 다른 곳(config.sh → 러너 서비스 → 각 액션)에서 재발 |
| 컨테이너 러너 + docker.sock 마운트 | 시도 안 함 | 게임 서버까지 있는 호스트에서 root 권한 노출은 blast radius가 너무 큼 |
| 컨테이너 러너 + SSH forced command + 범위 제한 sudoers | 채택 | 권한 최소화, 호스트 glibc와 무관 |

## 질문

- **Q. 왜 `develop` push를 트리거로 골랐나, `main`이 아니고?**
  A. 이 저장소는 이미 `rewrite/spring-boot-vite` 같은 작업 브랜치에서 개발하다가 배포 준비가
  되면 `develop`으로 머지하는 흐름을 쓰고 있었다. `develop`에 자동배포를 걸면 기존 흐름을
  그대로 "머지 = 배포 확정"이라는 의미로 재사용할 수 있다. 대신 이제 `develop`은 이름과 달리
  사실상 배포 브랜치가 됐다는 걸 팀(1인이지만)이 항상 인지하고 있어야 한다 — README에 경고를
  남겨둔 이유다.

- **Q. 컨테이너 재기동까지 완전 자동화 말고, 빌드/업로드까지만 자동화하고 재기동은 사람이
  누르게 두는 절충안도 있었는데 왜 완전 자동화로 갔나?**
  A. 처음엔 "완전 자동화는 blast radius가 크다"는 이유로 절충안(빌드+업로드만 자동, 재기동은
  수동 SSH)을 택했다. 하지만 모바일/사무실처럼 NAS에 SSH로 못 들어가는 상황에서 배포하고
  싶다는 요구가 나오면서, "재기동 권한을 안 주는 것"과 "재기동 권한을 스크립트 하나로
  극도로 좁혀서 주는 것" 중 후자가 실용성과 안전성을 더 잘 절충한다고 판단해 forced command
  방식으로 전환했다. 즉 "완전 자동화 여부"보다 "그 자동화가 얼마나 좁게 스코프됐나"가
  진짜 안전성을 결정한다.

- **Q. 이 방식이 정말 안전한가? SSH 키 하나가 결국 컨테이너 재기동을 트리거할 수 있는데.**
  A. 이 키로 할 수 있는 일은 딱 "지금 배포 디렉토리에 있는 jar로 컨테이너를 다시 빌드·재기동"
  뿐이다 — 임의 명령 실행, 다른 컨테이너 조작, 파일시스템 접근은 불가능하다. 남은 위험은
  "배포 디렉토리에 있는 jar 자체가 악의적으로 바뀌는 것"인데, 그건 이 SSH 키가 아니라
  워크플로우(→ GitHub 저장소 접근 권한)가 지켜야 할 경계다. 즉 이 설계는 "SSH 키 유출"의
  피해 범위를 "저장소가 이미 손상된 상황"과 같은 수준으로 낮춘 것이지, 저장소 자체의 보안을
  대체하진 않는다.

## 예시 코드

**워크플로우 정의** (`.github/workflows/deploy.yml`) — 러너가 NAS 자신이라 `cp`로 배포:

```yaml
name: Deploy Blog

on:
  push:
    branches: [develop]

jobs:
  deploy:
    runs-on: [self-hosted, nas]

    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 24

      - name: Build frontend
        working-directory: frontend
        run: |
          npm ci
          npm run build

      - name: Deploy frontend
        run: |
          rm -rf /volume1/web/rotten-noble/public/assets
          cp -r frontend/dist/. /volume1/web/rotten-noble/public/

      - name: Setup Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21

      - name: Build backend
        working-directory: backend-spring
        run: ./mvnw clean package -DskipTests

      - name: Deploy backend
        run: |
          cp backend-spring/target/backend-0.0.1-SNAPSHOT.jar /volume1/docker/rottennoble-backend/backend-0.0.1-SNAPSHOT.jar
          cp backend-spring/Dockerfile.nas /volume1/docker/rottennoble-backend/Dockerfile.nas
          cp backend-spring/deploy.sh /volume1/docker/rottennoble-backend/deploy.sh

      - name: Restart backend container
        run: |
          ssh -o StrictHostKeyChecking=no -i /run/deploy-ssh/id_ed25519 -p 8770 gabliw@127.0.0.1
```

**러너 컨테이너 실행** — docker.sock 마운트 없이, 배포 대상 경로와 SSH 키만 마운트:

```bash
sudo docker run -d \
  --name gha-nas-runner \
  --restart unless-stopped \
  --network host \
  -e REPO_URL=https://github.com/<user>/<repo> \
  -e RUNNER_TOKEN=<GitHub 등록 페이지에서 발급받은 1회용 토큰> \
  -e RUNNER_NAME=nas-docker-runner \
  -e LABELS=nas \
  -e RUNNER_WORKDIR=/_work \
  -e CONFIGURED_ACTIONS_RUNNER_FILES_DIR=/registration \
  -e DISABLE_AUTOMATIC_DEREGISTRATION=true \
  -v /volume1/docker/gha-docker-runner/registration:/registration \
  -v /volume1/docker/gha-docker-runner/work:/_work \
  -v /volume1/web/rotten-noble/public:/volume1/web/rotten-noble/public \
  -v /volume1/docker/rottennoble-backend:/volume1/docker/rottennoble-backend \
  -v /volume1/docker/gha-runner-ssh:/run/deploy-ssh:ro \
  myoung34/github-runner:latest
```

`DISABLE_AUTOMATIC_DEREGISTRATION=true`를 빼먹으면 앞서 설명한 재시작 무한 루프가 재발한다.

**최소 권한 SSH 키 등록** (`~/.ssh/authorized_keys`, NAS 쪽) — 이 키로는 딱 이 명령만 실행 가능:

```
command="sudo /bin/sh /volume1/docker/rottennoble-backend/deploy.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA... gha-nas-deploy
```

**범위 제한 NOPASSWD sudo** (`/etc/sudoers.d/gha-deploy`) — `docker` 전체가 아니라 이 스크립트만:

```
gabliw ALL=(root) NOPASSWD: /bin/sh /volume1/docker/rottennoble-backend/deploy.sh
```

**`deploy.sh`에 추가한 PATH 보정**:

```sh
set -e
export PATH="/usr/local/bin:$PATH"   # forced command는 로그인 셸이 아니라 PATH가 최소한만 잡힌다
cd "$(dirname "$0")"
```

### 로그 확인 예시

컨테이너 러너의 실시간 상태와 최근 job 결과:

```bash
sudo docker ps --filter name=gha-nas-runner        # Up 인지 Restarting 인지 확인
sudo docker logs gha-nas-runner --tail 50           # "Running job" / "Job ... completed with result: Succeeded"
```

### 실행(트리거) 예시

```bash
# 작업 브랜치에서 배포 브랜치로 머지하면 그 순간 배포가 시작된다
git checkout develop
git merge --ff-only rewrite/spring-boot-vite
git push origin develop
```

### 깃에서(GitHub 쪽) 확인 예시

- 저장소의 **Actions** 탭 → 워크플로우 실행 목록에서 초록 체크(성공)/빨간 X(실패) 확인.
- **Settings → Actions → Runners**에서 등록된 러너가 "Idle"(녹색, 대기 중)인지 "Offline"인지
  확인 — 컨테이너가 죽어있으면 여기서 바로 드러난다.
- 배포 후 실제 반영 확인은 결국 서비스 자체를 호출해보는 게 가장 확실하다:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://rotten-noble.com/
curl -s -o /dev/null -w "%{http_code}\n" https://api.rotten-noble.com/api/health
```

## 플로우차트

`GitHub-Actions.flow.md` 참고 — push부터 컨테이너 재기동까지 전체 파이프라인이 어느
경계(GitHub / 컨테이너 / NAS 호스트)를 넘나드는지 그린 그림.

## 실무

실무 규모의 팀에서는 이 프로젝트처럼 SSH 키 하나를 손으로 forced command에 끼워 넣는 대신,
클라우드 시크릿 매니저(AWS Secrets Manager, HashiCorp Vault)와 **ephemeral 러너**(작업 하나
끝나면 컨테이너째로 폐기되는 러너)를 조합해서 "이번 job이 다음 job의 상태에 영향을 주지 않게"
만드는 경우가 많다. 이 프로젝트가 그렇게까지 하지 않은 이유는 규모 때문이다 — 개인 NAS 한 대,
배포 빈도도 낮고, 애초에 컨테이너를 매번 새로 만들 만큼 빌드가 무겁지도 않다. **"완전 자동화된
파이프라인"이 항상 목표가 아니라, 지금 규모에서 반복 작업을 없애면서 사고 시 피해 범위를
좁히는 것**이 실제 목표였고, 그 기준에서는 지금 구조로 충분하다. 다만 이 NAS가 게임 서버
스택([Self-Hosting-vs-Cloud.md](Self-Hosting-vs-Cloud.md))까지 같이 떠받치고 있다는 점에서,
"권한을 최소한으로 준다"는 원칙만은 팀 규모와 무관하게 지켜야 하는 부분이었다.

## 같이 보기

- [Self-Hosting-vs-Cloud](Self-Hosting-vs-Cloud.md) — 애초에 이 NAS를 프로덕션 서버로 쓰기로
  한 결정, 그리고 그 결정이 오늘 겪은 glibc 문제의 근본 배경
- [Rate-Limiting](../Security/Rate-Limiting.md) — 같은 NAS/저장소에서 "기능 하나를 넣을 때
  실패 시 무엇이 더 나쁜가"를 먼저 따진 또 다른 사례 (Redis 연결 실패 시 통과 vs 여기서는
  sudoers 권한을 최소화)

## 참고자료

- [GitHub Actions — About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners)
- [myoung34/docker-github-actions-runner](https://github.com/myoung34/docker-github-actions-runner) — 이 프로젝트가 쓴 컨테이너 러너 이미지
- [OpenSSH authorized_keys — command= 옵션](https://man.openbsd.org/sshd#AUTHORIZED_KEYS_FILE_FORMAT)

## 개정 이력

| 날짜 | 무엇을 바꿨나 | 계기 |
|---|---|---|
| 2026-09-10 | 최초 작성 | `RottenNoble-Project` 배포를 GitHub Actions self-hosted 러너로 자동화하면서, 오래된 NAS의 glibc 비호환·컨테이너 재시작 루프·forced command PATH 문제를 실제로 겪고 해결한 과정을 정리 |
