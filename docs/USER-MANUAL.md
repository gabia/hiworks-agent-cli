# Hiworks Agent CLI 사용자 매뉴얼

`hac`는 Pi를 Hiworks 전용 설정으로 실행하는 CLI입니다. 터미널에서 코드 작업을 요청하고, 모델·스킬·확장 패키지를 사용할 수 있습니다. 별도로 설치된 시스템 `pi`와 실행 파일 및 사용자 설정을 분리합니다.

공식 소스 저장소는 [gabia/hiworks-agent-cli](https://github.com/gabia/hiworks-agent-cli)입니다. 설치 절차와 AI 에이전트용 실행 안내는 저장소 루트의 [README.md](../README.md)에서도 확인하실 수 있습니다.

## 목차

1. [처음 시작하기](#1-처음-시작하기)
2. [Gabia AI Hub 설정](#2-gabia-ai-hub-설정)
3. [실행과 도움말](#3-실행과-도움말)
4. [스킬과 추가 패키지](#4-스킬과-추가-패키지)
5. [업데이트와 복구](#5-업데이트와-복구)
6. [설정 파일과 백업](#6-설정-파일과-백업)
7. [문제 해결](#7-문제-해결)
8. [제거](#8-제거)
9. [고급 설정](#9-고급-설정)

## 1. 처음 시작하기

### 준비 사항

- macOS: `arm64`, `x64`, `x86_64`
- Linux: `arm64`, `aarch64`, `x64`, `x86_64`
- Node.js, npm, jq, 소스 복제·갱신에 사용할 Git
- npm 다운로드와 AI Hub 연결이 가능한 네트워크
- Gabia AI Hub에서 발급받은 API Key

macOS의 `aarch64` 표기는 지원하지 않습니다. Pi 0.85.1로 검증한 Node.js 요구사항은 **22.19.0 이상**입니다. hac 설치기의 최소 버전 검사와 별도로, 실제 내려받은 Pi의 Node 요구사항을 의존성 설치 단계에서 검사합니다.

```sh
node --version
npm --version
jq --version
git --version
```

### GitHub 소스 받기 → 설치 → 설정 → 실행

소스를 보관할 폴더에서 GitHub 저장소를 복제하고, 복제된 폴더로 이동해 설치합니다.

```sh
git clone https://github.com/gabia/hiworks-agent-cli.git
cd hiworks-agent-cli
sh ./install.sh --install
export PATH="$HOME/.local/bin:$PATH"
hac setup
hac
```

`--install`은 hac 파일 설치와 함께 Pi 활성화, Hiworks 리소스 및 기본 패키지 설치까지 진행합니다. `sh ./install.sh`만 실행하면 hac와 Pi 소스를 준비하고, 첫 `hac` 실행에서 관리 환경을 초기화합니다. 처음 설치하는 경우 위의 `--install` 방식을 권장합니다.

이미 해당 GitHub 저장소를 복제한 경우에는 저장소 루트에서 최신 소스를 받은 뒤 다시 설치합니다. 작업 중인 변경이 있다면 먼저 `git status --short`로 확인합니다. 갱신이 실패하면 원인을 확인하고 로컬 작업을 보존한 상태에서 처리해 주십시오.

```sh
git pull --ff-only
sh ./install.sh --install
export PATH="$HOME/.local/bin:$PATH"
hac version
```

GitHub에서 **Code → Download ZIP**으로 받은 소스도 압축을 푼 폴더에서 같은 설치 명령을 실행할 수 있습니다. ZIP 설치본은 `git pull` 대신 새 소스를 내려받아 갱신합니다.

새 터미널에서도 명령을 사용하려면 `export PATH="$HOME/.local/bin:$PATH"`를 사용하는 셸의 설정 파일(예: `~/.zshrc`)에 추가하세요.

```sh
hac version
hac doctor
```

`hac version`에서 활성 Pi 버전이 나오고 `hac doctor`의 `configuration`, `runtime`, `core`, `packages`가 `ok`이면 기본 상태가 정상입니다. 이것만으로 AI Hub 채팅 응답까지 검증되는 것은 아닙니다.

### AI 에이전트에게 설치 요청

터미널 명령을 실행할 수 있는 AI 에이전트에게 아래 내용을 전달합니다. 저장소를 복제하고 `README.md`를 읽는 것부터 설치 상태 확인까지 요청하는 예시입니다.

```text
https://github.com/gabia/hiworks-agent-cli 저장소를 복제하고 README.md를 읽어,
이 컴퓨터에 Hiworks Agent CLI(hac)를 설치해 주십시오.
지원 환경과 Git·Node.js·npm·jq를 확인한 뒤 저장소 루트에서
sh ./install.sh --install을 실행해 주십시오.
현재 셸과 셸 설정 파일에 PATH를 중복 없이 등록하고,
hac version과 hac doctor 결과를 확인해 주십시오.
기존 저장소나 작업을 덮어쓰지 마십시오.
인증 값이 없다면 설치를 먼저 완료하고 hac setup 방법을 안내해 주십시오.
API Key는 로그나 명령행 인자에 노출하지 마십시오.
```

에이전트가 대화형 터미널을 사용할 수 없으면 `hac setup` 대신 [옵션으로 연결하기](#옵션으로-연결하기)을 사용합니다. 사용자가 제공한 AI Hub 주소·모델 ID·키 파일 경로가 있어야 하며, 값을 임의로 만들어서는 안 됩니다.

## 2. Gabia AI Hub 설정

```sh
hac setup
```

### 설정 순서

1. **Base URL**: 처음에는 `https://ai-hub.gabia.com/v1`을 제안합니다. Enter로 수락하거나 다른 HTTPS 주소를 입력합니다. `/models`를 붙이지 말고 `/v1`까지 입력하세요.
2. **API Key**: 입력 내용은 터미널에 표시되지 않습니다. 같은 주소에 저장된 키가 있으면 Enter로 유지할 수 있습니다. 주소를 변경하면 키를 다시 입력해야 합니다.
3. **모델 조회**: `<Base URL>/models`에 인증 요청을 보내 사용할 수 있는 모델 ID 목록을 읽습니다.
4. **기본 모델 선택**: 표시된 번호 또는 모델 ID를 입력합니다. Enter는 표시된 기본값을 사용합니다. 기존 기본 모델이 목록에 있으면 유지하고, 그렇지 않으면 `glm`, 그다음 목록의 첫 모델을 제안합니다.

예시 화면의 모델 번호는 서버 응답에 따라 달라집니다.

```text
Hiworks Agent CLI — Gabia AI Hub setup
Base URL [https://ai-hub.gabia.com/v1]:
API Key (hidden):
Fetching available models…
1. glm (default)
2. kimi
Default model [glm] (number or model ID): 2
Saved 2 models. Default: gabia/kimi
Run hac to start.
```

이전 AI Hub 주소가 저장된 설치본은 최신 소스로 재설치한 뒤 `hac setup`을 실행합니다. 새 주소를 확인하고 API Key를 다시 입력하면 저장된 연결 주소도 갱신됩니다.

### 저장 내용과 재실행

| 파일 | 설정되는 내용 |
|---|---|
| `auth.json` | `gabia` API Key. 파일 권한은 `0600` |
| `models.json` | `gabia` provider의 주소, API 방식, 조회된 전체 모델 목록 |
| `settings.json` | `defaultProvider: gabia`, 선택한 `defaultModel` |

모든 파일은 `~/.config/hiworks-agent-cli/` 아래에 저장됩니다. API Key 자체는 `models.json`에 복사하지 않습니다.

`hac setup`은 여러 번 실행할 수 있습니다. 같은 서버 목록과 선택으로 실행하면 설정 내용이 동일하게 유지됩니다. 모델 목록은 중복 없이 동기화하고, 서버에서 사라진 Gabia 모델은 제거합니다. 다른 provider, 사용자 패키지와 관련 없는 설정은 유지합니다. 인증·조회 실패 또는 저장 전 취소 시 기존 설정은 변경하지 않습니다.

설정 완료 후 실행 중인 hac가 있다면 종료하고 다시 시작하세요. 모델 목록 조회 성공은 각 모델의 채팅·도구 호출 지원을 보장하지 않습니다.

### 옵션으로 연결하기

모델 ID를 이미 알고 있다면 기존 명령도 사용할 수 있습니다.

```sh
hac ai-hub connect --model glm
hac ai-hub connect --url https://ai-hub.gabia.com/v1 --model glm
hac ai-hub --help
```

자동화에서는 사용자에게 받은 주소·모델 ID·키 파일 경로로 연결합니다.

```sh
hac ai-hub connect \
  --url "$AI_HUB_URL" \
  --model "$AI_HUB_MODEL" \
  --api-key-stdin < "$AI_HUB_KEY_FILE"
```

이 명령은 선택한 모델을 검증·등록합니다. 전체 모델 목록을 새로 동기화하려면 `hac setup`을 사용하세요. 자동화에서는 비밀 관리 도구의 출력을 `--api-key-stdin`으로 전달할 수 있습니다. 키를 명령행 인자로 넣지 않습니다.

## 3. 실행과 도움말

```sh
hac
```

시작 헤더와 창 제목은 **Hiworks Agent CLI**입니다. pi-open-tui를 기반으로 입력창과 하단 상태 표시를 구성하며 모델·토큰·Git 정보를 제공합니다. 입력란에 작업을 자연어로 요청하세요.

일반 실행은 설치된 Pi 버전을 사용하며 매번 최신 버전으로 업그레이드하지 않습니다. 다만 처음 실행하거나 기본 패키지가 미등록 상태이면 설치가 필요할 수 있습니다.

### 터미널 명령

| 명령 | 용도 |
|---|---|
| `hac --help` / `hac -h` / `hac help` | hac 명령 목록과 사용 예시 |
| `hac --continue` / `hac -c` | 현재 폴더의 가장 최근 세션 이어가기 |
| `hac setup` | AI Hub 주소·키·모델 대화형 설정 |
| `hac usage` | hac에 연결된 AI Hub 키의 사용액·예산과 Codex(ChatGPT) 로그인의 구독 한도 조회 |
| `hac install` | 관리 환경과 누락된 기본 패키지 설치 |
| `hac install --repair` | Pi 재설치 및 관리 환경 복구 |
| `hac update` | hac 배포처와 npm의 최신 Pi 확인·업데이트 |
| `hac pi [인자...]` | 관리되는 Pi에 명령 전달 |
| `hac pi --help` | Pi 자체의 상세 도움말 |
| `hac pi update [--force]` | Pi 본체만 최신화, `--force`는 동일 버전 재설치 |
| `hac doctor` | 설정·런타임·리소스 등 진단 |
| `hac version` | hac·Pi·core 버전과 활성 경로 |
| `hac uninstall` | hac 설치 파일 제거, 사용자 데이터 유지 |

`hac pi --help`에 나오는 명령은 앞의 `pi`를 `hac pi`로 바꾸어 사용합니다. **`update`는 예외**입니다. hac가 직접 처리하므로 Pi 도움말의 `--all`, `--extensions`, 특정 패키지 업데이트 인자는 전달하지 않습니다. 지원 범위는 `hac pi update --help`로 확인하세요.

### 실행 화면 안의 명령

터미널의 `hac ...` 명령과 Pi 입력란의 `/...` 명령은 다릅니다.

```text
/settings
/skill:hiworks-development
/skill:brainstorming
/skill:systematic-debugging
/usage
```

`/usage`는 현재 세션에서 사용 중인 모델의 provider 기준으로 사용현황을 보여 줍니다. `/model`로 모델을 바꾸면 바뀐 모델의 provider를 따릅니다. 터미널의 `hac usage`는 hac에 연결된 지원 provider를 모두 보여 주며 기본 provider(`settings.json`)를 먼저 표시합니다.

- **AI Hub (`gabia`)**: 사용액·예산·초기화 시각. 개인 키로는 모델별 내역 없이 총 사용액과 예산을 조회합니다.
- **Codex (`openai-codex`)**: hac 안에서 `/login`으로 연결한 ChatGPT 계정의 5시간·주간 한도 사용률과 초기화 시각. 조회에 쓰는 엔드포인트는 비공개라 예고 없이 바뀔 수 있습니다. 사용현황 조회 때 토큰이 만료되어 있으면 관리 Pi가 자체 OAuth 갱신을 시도하고, 갱신에 실패하면 `/login`을 다시 하세요.

`/`를 입력하면 실행 환경에서 사용할 수 있는 명령을 확인할 수 있습니다. 세션 종료와 단축키 등 상세 조작은 Pi 도움말을 참고하세요.

### Hiworks 화면과 배경색

Hiworks 사이트의 파란색을 기준으로 밝은 화면·어두운 화면용 팔레트를 제공합니다. 기본 `auto`는 터미널의 `COLORFGBG` 힌트를 우선 사용하고, 없으면 Pi 시작 테마 이름을 기준으로 선택합니다. 모든 터미널의 배경색을 정확히 감지할 수 있는 것은 아닙니다. 글자가 흐리거나 배경과 어울리지 않으면 직접 선택하세요.

Pi 입력란에서:

```text
/hiworks-theme light
/hiworks-theme dark
/hiworks-theme auto
/hiworks-ui
```

`/hiworks-theme`만 입력하면 선택 목록이 나옵니다. 선택은 hac 설정 폴더의 `hiworks-theme.json`에 저장되어 다음 실행에도 적용됩니다. `/hiworks-ui`에서는 헤더·푸터, 표시 항목, 커서와 아이콘 등을 조정합니다(`hiworks-ui.json`). 기본 아이콘은 별도 Nerd Font가 필요 없는 ASCII입니다. 일반(General) 탭의 언어(Language) 항목에서 한국어·영어를 전환할 수 있습니다. 선택은 저장되며, 이전 중국어 설정은 한국어로 읽어들입니다.

터미널에서 실행별로 지정할 수도 있습니다.

```sh
HAC_THEME=light hac
HAC_THEME=dark hac
HAC_THEME=auto hac
```

환경 변수는 **시작 시 저장된 선택보다 우선**합니다. 실행 중 명령으로 바꾸면 즉시 적용되지만 다음 실행에 같은 환경 변수를 사용하면 다시 그 값이 우선합니다. 터미널 자체의 배경색이나 Pi의 `settings.json` 테마는 변경하지 않습니다. 실행 중 터미널 배경을 바꿨다면 `/hiworks-theme`으로 다시 선택하세요. `hac pi install` 같은 관리 명령이나 비대화형 출력에는 화면 확장을 적용하지 않습니다.

원본 pi-open-tui를 별도로 동시에 로딩하면 헤더·입력창 확장이 충돌할 수 있으므로 hac에 포함된 확장만 사용하세요. 원본 버전과 MIT 라이선스는 [출처 안내](../resources/hac-branding/PROVENANCE.md)에 기록했습니다.

## 4. 스킬과 추가 패키지

### 기본 제공 항목

- `hiworks-development`: Hiworks 개발 지침. hac가 관리 스킬 경로를 전달합니다.
- 기본 npm 패키지: 저장소의 [`manifest/default-packages.json`](../manifest/default-packages.json)에 선언합니다. 현재 실제 목록은 이 파일이 기준입니다.
- `pi-anthropic-oauth`: 현재 기본 목록에 포함된 추가 패키지입니다. 설치와 공급자 인증 완료는 별개이며, 사용 방법은 해당 패키지 안내를 따릅니다.
- `pi-superpowers-plus@0.4.1`: 기본 목록에 포함된 워크플로 패키지로 스킬 12개와 확장을 제공합니다. 별도 복사된 스킬 번들을 유지하지 않습니다.

기본 패키지는 `hac install` 또는 `hac` 실행에서 Pi의 `install` 기능으로 설치합니다. 같은 패키지가 이미 등록되어 있으면 건너뛰고, 사용자가 선택한 다른 버전도 유지합니다. 기본 패키지를 제거해도 목록에 남아 있으면 다음 `hac` 실행에서 다시 설치됩니다.

### 나만의 패키지 추가

```sh
hac pi install npm:패키지명
hac pi install npm:패키지명@1.2.3
hac pi install /절대경로/my-package
hac pi install git:github.com/조직/저장소
```

기본적으로 hac 사용자 설정에 등록되며, 다시 실행하면 패키지의 스킬·확장을 로딩합니다. 현재 프로젝트에만 적용하려면 `-l`을 사용합니다.

```sh
hac pi install npm:패키지명 -l
```

프로젝트 설치는 `.pi/settings.json`에 등록됩니다. 프로젝트 신뢰 설정에 따라 로딩이 제한될 수 있습니다.

```sh
hac pi list                      # 설치 목록
hac pi config                    # 스킬·확장 등 활성화 설정
hac pi remove npm:패키지명        # 사용자 패키지 제거
hac pi remove npm:패키지명 -l     # 프로젝트 패키지 제거
```

현재 hac는 패키지 일괄 업데이트 명령을 제공하지 않습니다. 특정 버전으로 바꾸려면 `hac pi install npm:패키지명@새버전`을 사용하세요. `hac pi update`는 Pi 본체를 대상으로 합니다.

## 5. 업데이트와 복구

```sh
hac update
hac pi update
hac pi update --force
```

| 명령 | 바뀌는 대상 |
|---|---|
| `hac update` | 구성된 배포처의 hac와 npm 최신 Pi |
| `hac pi update` | npm 최신 안정 Pi만. core와 사용자 패키지 유지 |
| `hac pi update --force` | 이미 최신이어도 Pi를 재설치 |

현재 hac 자체 배포처가 없으면 다음과 같이 안내하고 Pi 최신화를 계속합니다.

```text
hac: no release feed configured; skipping hac self-update and updating Pi
```

이 안내는 실패가 아닙니다. hac 자체의 온라인 업데이트에는 실제로 내려받을 수 있는 release manifest와 archive가 필요합니다. Git 등록만으로 자동 배포되지 않습니다. 배포 설정은 [개발·배포 안내](DEVELOPMENT.md)를 참고하세요.

Pi 업데이트는 설치용 `HAC_PI_VERSION`, `HAC_PI_SOURCE`, `HAC_PI_PACKAGE_DIR` 값에 고정되지 않고 온라인 최신 안정 버전을 조회합니다. 후보의 버전·도움말을 검증한 후 활성화합니다. 다운로드나 검증 실패 시 기존 활성 Pi를 유지합니다. 예기치 않은 시스템 종료까지 완전히 원자적인 복구를 보장하는 것은 아닙니다.

### 실행 직후 종료되거나 관리 파일이 손상된 경우

```sh
unset HAC_PI_SOURCE HAC_PI_PACKAGE_DIR HAC_PI_VERSION
hac install --repair
hac pi --version
hac doctor
```

복구는 기본적으로 npm 최신 Pi를 다시 설치합니다. API Key, 모델, 세션은 유지합니다. 기본 패키지 설치는 별도 단계이므로 이 단계에서 실패하면 네트워크 등을 해결한 뒤 `hac install`을 다시 실행하세요.

## 6. 설정 파일과 백업

```text
~/.local/bin/hac                  # 사용자 실행 명령
~/.local/share/hac/               # hac 코드, 기본 목록, UI 확장
~/.config/hiworks-agent-cli/
├── auth.json                    # 인증정보
├── models.json                  # provider와 모델 목록
├── settings.json                # 기본 모델, 사용자 패키지 등
├── npm/                         # Pi가 설치한 npm 패키지
├── git/                         # Pi가 설치한 Git 패키지
├── resources/                   # Hiworks core 리소스
├── packages/pi-managed/         # hac required package 상태 기록
├── runtime/                     # Pi 릴리스, 활성 포인터, 잠금
├── sessions/                    # 대화 세션
└── logs/
```

설정 root는 `$HOME/.config/hiworks-agent-cli`로 고정하며 `XDG_CONFIG_HOME`으로 변경하지 않습니다. `hac pi`는 시스템 `pi`를 검색하지 않고 이 경로의 관리 릴리스를 실행합니다.

설정과 대화를 보존하려면 hac를 종료한 뒤 전체 설정 디렉터리를 접근 제한된 위치에 백업하세요. 백업에도 API Key가 포함됩니다. 프로젝트별 `.pi/` 설정은 해당 프로젝트에서 별도로 관리합니다. 재설치나 Pi 업데이트는 사용자 데이터를 삭제하지 않지만, `hac setup`과 패키지 명령은 요청한 설정 항목을 갱신합니다.

## 7. 문제 해결

| 증상 | 확인 및 조치 |
|---|---|
| `hac: command not found` | `~/.local/bin`을 PATH에 추가하고 새 터미널에서 실행 |
| `jq is required` | jq 설치 후 재시도 |
| Pi 의존성 설치 실패 | Node 버전과 npm 로그, registry/proxy 연결 확인 |
| `HTTP 401` / `403` | `hac setup`에서 API Key와 접근 권한 확인 |
| 모델 목록 없음 / 선택한 모델 없음 | Base URL이 `/v1`까지인지 확인하고 `hac setup` 재실행 |
| TLS 인증서 오류 | OS 신뢰 인증서, Node의 시스템 CA 지원 또는 `NODE_EXTRA_CA_CERTS` 확인 |
| `managed installation needs repair` | `hac install --repair` 실행 |
| 기본 패키지 설치 실패 | npm 연결 확인 후 `hac install` 재실행 |
| 스킬이 목록에 없음 | hac 재시작, `hac pi list`와 `hac pi config` 확인. 직접 만든 SKILL.md에는 `name`·`description` 메타데이터 필요 |
| `network=not-checked` | doctor가 네트워크를 조회하지 않았다는 뜻. 연결 실패를 의미하지 않음 |
| `hacReleaseFeed=unconfigured` | hac 배포처 미설정. Pi 업데이트는 사용 가능 |
| `auth.json must be 0600` | `chmod 600 ~/.config/hiworks-agent-cli/auth.json` |
| `lock is held` | 다른 설치·업데이트·설정 작업이 진행 중인지 확인. 진행 중인 작업의 잠금은 삭제하지 않음 |

```sh
hac doctor
hac version
hac --help
hac pi --help
```

doctor는 설정 JSON, 인증 파일 권한, 플랫폼, Pi 버전·도움말 실행, core 파일 구조 및 required package 상태 등을 확인합니다. 모든 스킬·확장의 실행이나 AI Hub 채팅까지 확인하지는 않습니다.

## 8. 제거

```sh
hac uninstall
```

실행 파일과 hac 설치 디렉터리를 제거하고 사용자 설정·패키지·세션은 남깁니다.

모든 hac 사용자 데이터까지 삭제하려는 경우에만 다음을 사용하세요.

```sh
hac uninstall --purge
```

확인 질문 없이 삭제하려면 `hac uninstall --purge --yes`를 사용합니다. 삭제 대상에는 API Key와 대화 세션도 포함됩니다. 프로젝트의 `.pi/`와 별도로 설치된 시스템 Pi는 제거하지 않습니다.

## 9. 고급 설정

일반 사용자는 아래 변수를 설정할 필요가 없습니다.

| 변수 | 용도 |
|---|---|
| `HAC_PI_SOURCE` | 검증된 로컬 Pi 릴리스로 설치 |
| `HAC_PI_PACKAGE_DIR` | 로컬 npm 패키지 디렉터리로 설치 |
| `HAC_PI_VERSION` | 명시적 설치 버전 지정 |
| `HAC_DEFAULT_PACKAGES_FILE` | 기본 패키지 목록 JSON의 대체 파일 |
| `HAC_RELEASE_URL` | hac release manifest의 HTTPS 주소 |
| `HAC_INSTALL_ROOT`, `HAC_BIN_DIR` | 설치·제거 경로 변경. 사용 시 일관되게 지정 |
| `NODE_EXTRA_CA_CERTS` | 추가 신뢰 인증서 파일 |

오프라인 설치는 Pi 소스뿐 아니라 필요한 기본 패키지도 준비해야 합니다. 기본 패키지 자동 설치를 제외하는 환경에서는 별도 목록을 만드세요.

```json
{"packages":[]}
```

```sh
HAC_DEFAULT_PACKAGES_FILE=/절대경로/default-packages.json \
HAC_PI_SOURCE=/절대경로/verified-pi-release ./install.sh --install
```

해당 정책을 이후 실행에도 적용하려면 같은 변수를 유지해야 합니다. Pi 소스의 형식, 배포 파일 생성, 테스트 실행은 [개발·배포 안내](DEVELOPMENT.md)에 정리되어 있습니다.
