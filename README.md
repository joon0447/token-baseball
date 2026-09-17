# TokenBaseball

AI 토큰 사용 기록으로 재화를 얻고, 선수 카드를 수집해 야구단을 구성하는 macOS 앱입니다.

## 실행

macOS 14 이상과 Swift 6을 지원하는 Xcode/Command Line Tools가 필요합니다. 외부 패키지 의존성은 없습니다.

```sh
bash scripts/build-app.sh
open build/TokenBaseball.app
```

개발 중에는 `swift run TokenBaseball`로 실행할 수도 있습니다. Xcode에서 `Package.swift`를 열면 소스를 편집하고 실행할 수 있습니다.

## 처음 사용하기

1. 설정에서 **Codex**와 **Claude Code**의 ‘기본 폴더 연결’을 누릅니다. 기본 위치가 다르면 ‘폴더 선택’으로 연결합니다. 한 서비스만 사용해도 됩니다.
2. ‘사용량 반영’을 누르면 로컬 기록을 읽고 토큰을 볼로 환산합니다. 기록이 많으면 시간이 걸리며 취소할 수 있습니다.
3. 카드 상점에서 선수를 영입합니다.
4. 보유 카드에서 이름·사진을 바꾸거나, 내 선수단에서 포지션에 배치합니다.

기록은 자동으로 주기 갱신하지 않습니다. 홈·설정의 ‘사용량 반영’ 또는 `⌘R`로 새 기록을 읽습니다. 같은 기록은 중복 지급하지 않습니다.

## 저장과 테스트

진행 내용은 `~/Library/Application Support/TokenBaseball/state.json`에 저장합니다. 원본 AI 로그는 수정하지 않으며 대화 본문을 앱에 저장하거나 외부로 전송하지 않습니다.

```sh
swift test
bash scripts/build-app.sh release
```

테스트 데이터와 실제 진행 내용을 분리하려면 다음과 같이 실행합니다.

```sh
swift run TokenBaseball --data-directory /tmp/tokenbaseball-demo
```

초기 정책은 **1,000토큰 = 1볼**, 카드 가격 **10 / 30 / 100볼**입니다. 최종 확정 전 개발용 값입니다. 정책 변경 시 기존 저장 파일을 처리할 마이그레이션도 함께 구현해야 합니다.

## 개발 문서

- [기능 구현 목록](docs/기능-구현-목록.md)
- [개발 규칙과 초기 정책](docs/개발-규칙.md)
- [구현 및 검증 결과](docs/구현-검증-결과.md)
- [Codex 기록 형식](docs/codex-usage-format.md)
- [Claude Code 기록 형식](docs/claude-usage-format.md)

현재 앱 번들은 이 Mac에서 실행·검증하기 위한 개발용 서명입니다. 외부 배포용 서명·공증은 후속 작업입니다.
