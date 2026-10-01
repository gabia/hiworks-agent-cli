# Hiworks Agent CLI (`hac`)

터미널에서 AI에게 코드 작성, 수정, 테스트를 요청하는 CLI입니다. Pi coding agent 기반이며 Gabia AI Hub를 연결해 사용합니다.

## 설치 방법

macOS·Linux(ARM64 또는 x64)에서 사용할 수 있습니다. Windows에서는 WSL을 이용합니다. Git, Node.js 22.19.0 이상, npm, jq가 필요합니다. 설치할 Pi 버전이 더 높은 Node.js 버전을 요구하면 업데이트해 주십시오.

```sh
git clone https://github.com/gabia/hiworks-agent-cli.git
cd hiworks-agent-cli
sh ./install.sh --install
export PATH="$HOME/.local/bin:$PATH"
hac version
```

새 터미널에서도 사용하려면 `export PATH="$HOME/.local/bin:$PATH"`를 `~/.zshrc` 또는 `~/.bashrc`에 추가합니다.

AI Hub 연결은 다음 명령으로 설정합니다. 기본 주소는 `https://ai-hub.gabia.com/v1`이며, API Key를 입력하고 모델을 선택합니다.

```sh
hac setup
hac doctor
```

## 사용 방법

작업할 프로젝트 폴더에서 실행합니다.

```sh
cd /path/to/project
hac
```

입력란에 원하는 작업을 작성합니다. 예: "로그인 오류를 수정하고 테스트를 실행해 주세요."

| 명령 | 용도 |
|---|---|
| `hac --continue` | 이전 작업 이어가기 |
| `hac pi --print "작업 내용"` | 화면 없이 작업 실행 |
| `hac doctor` | 설치 상태 확인 |
| `hac pi update` | Pi 업데이트 |

hac 화면에서는 `/model`로 모델을 선택하고, `/settings`로 설정을 변경합니다.

소스에서 hac를 업데이트하려면 복제한 저장소에서 실행합니다.

```sh
git pull --ff-only
sh ./install.sh --install
```

## AI 에이전트로 설치

사용 중인 에이전트에게 아래 요청을 전달합니다.

```text
https://github.com/gabia/hiworks-agent-cli를 복제하고 README.md에 따라 hac를 설치해 주세요.
필수 도구와 PATH를 확인하고 hac version, hac doctor로 설치를 검증해 주세요.
AI Hub 인증은 사용자에게 안내하고, API Key를 로그에 남기지 마세요.
```

자동화 환경의 인증 방법은 [사용자 매뉴얼](docs/USER-MANUAL.md)을 참고합니다.

## 문서 및 라이선스

[사용자 매뉴얼](docs/USER-MANUAL.md) · [HTML 매뉴얼](https://gabia.github.io/hiworks-agent-cli/USER-MANUAL.html) · [개발 안내](docs/DEVELOPMENT.md)

[MIT License](LICENSE). 외부 코드와 패키지의 라이선스는 [외부 소프트웨어 고지](THIRD_PARTY_NOTICES.md)를 참고합니다.
