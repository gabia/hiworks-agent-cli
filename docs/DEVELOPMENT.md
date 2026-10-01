# 개발·배포 안내

사용자 설치와 사용법은 [사용자 매뉴얼](USER-MANUAL.md)을 참고합니다. 이 문서는 유지보수자와 배포 담당자를 대상으로 합니다.

## 구성

| 경로 | 책임 |
|---|---|
| `bin/hac` | 명령 분기, 시스템 CA 설정 |
| `install.sh` | hac 설치 스테이징, 기존 설치 백업·복원 |
| `lib/hac-commands.sh` | 설치·실행·진단·업데이트·제거·도움말 |
| `lib/hac-pi-source.sh` | npm 최신 버전 조회, 소스 획득·정규화 |
| `lib/hac-runtime.sh` | 버전·도움말 실행 검증, 릴리스 활성화·복구 |
| `lib/hac-packages.sh` | Pi 명령 전달, required/default package 설치 |
| `lib/hac-setup.mjs` | Gabia 대화형 설정과 모델 선택 |
| `lib/hac-ai-hub.mjs` | 인증·모델 조회, 설정 병합·저장 |
| `lib/hac-update.mjs` | hac HTTPS release 다운로드·검증·교체 |
| `manifest/core.json` | core 리소스 계약과 required package 정책 |
| `manifest/default-packages.json` | 사용자 환경에 자동 등록할 기본 npm 패키지 |
| `manifest/hac.json` | hac 자체 버전 |
| `resources/hiworks-core` | 관리 스킬과 core 파일 |
| `resources/hac-branding/hiworks-theme.mjs` | Hiworks 테마와 pi-open-tui 포크의 진입점 |
| `scripts/package-release.mjs` | 배포 archive와 checksum manifest 생성 |

Pi 원본을 패치하지 않습니다. 최신 패키지의 `bin.pi` 진입점을 읽어 정규화하고, CLI 리소스 인자로 스킬·브랜딩 확장을 전달합니다. 업데이트 뒤에도 UI API 호환성은 실제 Pi로 확인해야 합니다.

## 런타임과 설치

정규화한 릴리스는 다음 형식입니다.

```text
pi-release/
├── metadata.json
├── bin/pi
└── package/       # npm 기반 소스의 실제 패키지와 의존성
```

```json
{"piVersion":"0.85.1","executable":"bin/pi"}
```

버전은 안정 버전 `X.Y.Z`이며 실제 실행 결과와 일치해야 합니다. 소스의 심볼릭 링크를 거부하고 archive 경로와 파일 유형을 검증합니다. 의존성은 `--engine-strict --ignore-scripts --no-bin-links`로 설치합니다. npm의 공개 shrinkwrap에 누락된 항목이 있을 수 있어 `npm install`로 정합성을 맞춥니다.

릴리스는 설정 root의 `runtime/releases/pi-VERSION`에 저장합니다. `active.json`에는 설정 root 내부 상대 실행 경로를 기록하고, 이전 포인터는 `active.json.previous`로 유지합니다. 버전·도움말 프로브는 별도 HOME에서 각각 시간 제한을 두고 실행합니다.

`./install.sh`는 hac와 Pi 소스를 준비합니다. `./install.sh --install`은 관리 환경 활성화도 수행합니다. 일반 `hac install`은 정상 릴리스가 있으면 재설치를 건너뛰지만 기본 패키지 누락을 확인합니다. `--repair`는 재설치를 강제합니다. 기본 패키지 설치 실패는 Pi 릴리스 전체 롤백과 별개이므로 재시도가 필요할 수 있습니다.

## 기본 패키지 정책

`manifest/default-packages.json`의 `packages` 배열에 `npm:` source를 선언합니다. `hac install`과 `hac` 실행에서 미등록 패키지를 Pi 자체의 `install` 명령으로 추가합니다. 버전이 다른 동일 패키지를 사용자가 이미 등록했다면 그 선택을 유지합니다. 목록에서 지웠다는 이유로 사용자의 기존 패키지를 자동 제거하지 않습니다.

`HAC_DEFAULT_PACKAGES_FILE`로 목록을 바꿀 수 있습니다. 테스트는 비어 있는 fixture를 사용해 npm 설치를 차단하며, 기본 패키지 테스트가 추가 설치·중복 방지·기존 설정 보존을 별도로 확인합니다.

이는 `manifest/core.json`의 `required` 계약과 다릅니다. required 항목은 exact npm 버전 또는 Git commit을 요구하고 상태 파일과 설치 목록을 검사합니다. 현재 core의 required 목록은 비어 있습니다. core의 버전·파일 정책을 변경할 때는 저장소 manifest와 배포용 `resources/hiworks-core/manifest.json`의 관계도 확인하세요. 기존 core 릴리스는 파일이 존재하면 재사용되므로 파일 변경을 자동 마이그레이션한다고 가정하지 않습니다.

## Gabia 설정 계약

`hac setup`은 HTTPS base URL과 비공개 키 입력을 받고 `/models`를 조회한 후 모델 선택을 요청합니다. 조회된 ID를 정렬·중복 제거하고 Gabia 모델 목록을 교체합니다. 기존 모델별 사용자 속성은 같은 ID에 병합하고 다른 provider는 유지합니다. `hac ai-hub connect`는 기존 호환 명령으로 선택한 한 모델을 병합합니다.

모델 조회·선택이 끝난 후 설정을 다시 읽고, 전용 잠금 아래 임시 파일을 생성하여 rename으로 공개합니다. 동기 파일 저장 단계에서 실패하면 이미 교체한 파일을 복원합니다. 이는 전원 손실에 대한 다중 파일 원자적 저장 보장은 아닙니다. 다른 도구가 동일 설정을 동시에 편집하지 않는 상태에서 사용하세요.

API Key는 `auth.json`에만 저장합니다. 로그·테스트·문서에 실제 키를 넣지 않습니다. 주소 변경 시 저장된 키를 자동 재사용하지 않습니다. 동일 서버/입력/응답으로 반복 실행한 결과가 동일한지 검사합니다. 모델 조회와 사용량 조회는 HTTPS만 허용하며, URL의 사용자 인증 정보·query·fragment도 요청 전에 거부합니다.

`hac`와 설치기는 `umask 077`을 적용합니다. 관리 디렉터리는 생성할 때와 기존 설치를 사용할 때 모두 `700`으로 제한하고, AI Hub 연결에서도 설정 root를 `700`으로 보호합니다. 인증파일은 `600`으로 저장하며 Pi가 새로 작성하는 세션·로그도 소유자에게만 읽기·쓰기를 허용합니다. 기존 세션 파일의 내용과 권한은 일괄 변경하지 않으며, 상위 관리 디렉터리를 통해 다른 사용자의 접근을 차단합니다.

## 온라인 배포

현재 hac 자체 배포 주소는 지정되어 있지 않습니다. Git commit/push와 배포 파일 게시는 별개입니다.

`scripts/package-release.mjs`는 루트 `LICENSE`, `THIRD_PARTY_NOTICES.md`와 `resources/licenses/`의 원문을 archive에 포함하고, `install.sh`는 같은 고지를 설치 root에 보존합니다. 기존 `resources/hac-branding/LICENSE`도 유지합니다. Pi와 기본 패키지는 설치 시 별도로 내려받으므로, 이 archive의 고지 목록만으로 향후 자동 설치되는 모든 버전의 검토가 완료되는 것은 아닙니다.

릴리스의 `docs/`에는 `USER-MANUAL.md`, `DEVELOPMENT.md` 두 파일만 포함합니다. 로컬 이메일·HTML 매뉴얼·스크린샷·추가 메모는 자동으로 포함하지 않습니다. 새 공개 문서나 이미지가 필요하면 내용을 검토한 뒤 패키징 도구의 허용 목록과 보존 테스트를 갱신합니다. `.pi/`, `.idea/`와 원본 이메일은 Git 제외 목록으로 관리합니다.

1. `manifest/hac.json`의 버전과 문서·테스트를 갱신합니다.
2. 아래 명령으로 배포 파일을 만듭니다. 예시 URL을 실제 공개 주소로 바꿉니다.
3. 생성된 archive와 manifest를 해당 HTTPS 호스트에 게시합니다.
4. 사용자 환경에 `HAC_RELEASE_URL` 또는 `updates.json`의 `hacReleaseUrl`을 지정합니다.

```sh
node scripts/package-release.mjs https://downloads.example.com/hac-1.1.0.tar.gz /tmp/hac-release
```

생성 파일:

- `hac-1.1.0.tar.gz`: `hac/`를 최상위로 하는 ustar archive
- `hac-release.json`: `version`, archive `url`, `sha256`

```json
{"hacReleaseUrl":"https://downloads.example.com/hac-release.json"}
```

이 설정은 `~/.config/hiworks-agent-cli/updates.json`에 저장합니다. manifest와 archive는 리다이렉트 없는 HTTPS URL이어야 합니다. archive에는 symlink·특수 파일·상위 디렉터리 경로를 허용하지 않습니다. 패키징 도구는 허용한 소스 디렉터리만 포함합니다.

`hac update`는 후보 hac 버전 검증 → 후보로 Pi 최신화 → hac 교체 순서로 진행합니다. Pi 활성 포인터와 hac 교체는 runtime 잠금 아래에서 처리합니다. 일반 오류에는 복원하고, 교체 중 SIGINT/SIGTERM은 교체·복원이 끝날 때까지 지연합니다. SIGKILL·전원 손실에는 수동 복구가 필요할 수 있습니다. 자체 배포처가 없으면 명시적으로 안내하고 Pi 업데이트만 수행합니다.

## UI 포크 유지보수

`resources/hac-branding/PROVENANCE.md`에 원본 커밋·라이선스·변경 범위를 기록합니다. 원본의 입력창·푸터를 유지하고 헤더와 설정 이름, 테마를 조정했습니다. 일부 스크롤 호환 코드는 Pi 내부 구조에 의존하므로 Pi 업데이트 시 실제 화면을 검증해야 합니다. 내부 transcript 접근을 사용하는 thinking peek는 기본적으로 꺼져 있습니다.

런타임 의존성은 관리 Pi의 확장 로더가 제공합니다. 루트 `package.json`과 lockfile은 개발 검증용이며 사용자 설치 시 node_modules를 복사하지 않습니다. 개발 검증용 Pi 패키지는 수정된 `undici 8.10.2`가 포함된 0.87.1로 맞춥니다. 설치·복구 계약의 오프라인 fixture는 0.85.1이며, 실제 라이브러리와 fixture의 검증 범위는 다릅니다.

```sh
npm ci --ignore-scripts
npm run test:theme
npm run typecheck:theme
python3 tests/pi_theme_smoke.py /absolute/path/to/pi /tmp/hac-theme-captures
```

마지막 명령은 임시 HOME에서 실제 light/dark TUI를 실행해 ANSI 화면을 저장하며 모델 요청을 보내지 않습니다. 세 번째 인자로 독립 설치된 확장 진입점을 지정할 수 있습니다. 테마의 기본 배경은 터미널이 결정하고 JSON의 배경 토큰은 메시지·도구 패널 등에 적용됩니다.

## 검증

```sh
sh tests/run.sh
```

전체 테스트는 셸 문법, 설정 경로, 리소스, 패키지, 설치, 업데이트, 복구, CLI, 키 숨김 입력, setup 멱등성, UI 확장을 검사합니다. 네트워크 대신 fixture를 사용하므로 CI 통과가 실서비스·실제 최신 Pi와의 호환성을 보장하지 않습니다.

```sh
# 자동 설치 경로의 결정적 smoke
HAC_SMOKE_NPM_FIXTURE=tests/fixtures/pi-package-0.85.1 sh tests/smoke.sh

# 검증된 실제 Pi source의 실행 smoke
HAC_PI_VERSION=0.85.1 HAC_PI_SOURCE=/absolute/path/to/pi-release sh tests/smoke.sh

# 실제 대화형 UI와 Hiworks 헤더 (Python 3 필요)
HAC_DEFAULT_PACKAGES_FILE="$PWD/tests/fixtures/default-packages-empty.json" \
HAC_PI_SOURCE=/absolute/path/to/pi-release sh tests/interactive-smoke.sh
```

Smoke는 별도 임시 HOME을 사용합니다. `PASS`, `SKIP`, `FAIL`을 구별하며, 필요한 도구나 실제 source가 없는 경우의 `SKIP`은 실제 실행 검증 통과가 아닙니다. 테스트 fixture를 사용자의 실제 Pi로 설치하지 않습니다.

실서비스 검증은 `hac setup`에서 실제 모델 목록 조회, 반복 실행 시 설정 동일성, `hac`의 실제 대화형 화면, Pi RPC 명령 목록의 스킬 등록을 확인합니다. API Key를 CI에 요구하거나 테스트 로그에 출력하지 않습니다. 개별 모델의 채팅 요청은 별도 검증입니다.

## 변경 기록

현재 사용 계약은 사용자 매뉴얼과 실행 코드가 기준입니다.
