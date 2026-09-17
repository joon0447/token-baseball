# TokenBaseball

Codex·Claude Code에서 사용한 토큰으로 뽑기 카드를 받고, 야구 선수단을 만드는 macOS 앱입니다.

## 실행

macOS 14 이상, Swift 6을 지원하는 Xcode/Command Line Tools가 필요합니다. 외부 패키지 의존성은 없습니다.

```sh
bash scripts/build-app.sh release
open build/TokenBaseball.app
```

Xcode에서 `Package.swift`를 열거나 `swift run TokenBaseball`로 개발할 수 있습니다.

## 사용 방법

1. 첫 실행부터 무작위 이름의 루키 선수 9명이 각 포지션에 배치됩니다.
2. 설정에서 Codex·Claude Code의 기본 기록 폴더를 연결합니다. 다른 위치는 ‘폴더 선택’을 사용합니다.
3. 토큰 누적 50M마다 뽑기 카드 1장이 생깁니다. ‘선수 뽑기’에서 카드를 열면 새로운 선수를 받습니다.
4. 보유 카드에서 이름·사진을 바꾸고, 내 선수단의 야구장 카드나 하단 목록에서 같은 포지션의 선수를 교체합니다.

등급 확률은 **루키 75% · 올스타 20% · 레전드 5%**입니다. 선수의 포지션은 고정이며, 뽑기는 누적 토큰을 차감하지 않습니다. K·M·B는 각각 천·백만·십억 토큰입니다.

## 오늘 사용량

macOS 상태바에서 오늘 사용한 토큰을 확인할 수 있습니다. 프로그램 실행 중 연결된 기록을 1분마다 갱신하며, 창을 닫아도 상태바는 남습니다. ‘종료’를 선택하면 표시와 갱신이 함께 종료됩니다.

Mac의 날짜·시간대를 사용하고 기록 자체의 타임스탬프로 집계합니다. 날짜가 없는 기록은 누적 토큰에만 포함합니다. 최초 기록 읽기는 시간이 걸릴 수 있으며, 이후에는 변경된 파일만 다시 읽습니다. 홈·설정·상태바에서 수동 갱신과 취소도 가능합니다.

## 저장과 이전 버전

`~/Library/Application Support/TokenBaseball/state.json`에 진행 내용을 저장합니다. v0.1 데이터는 `state.json.v1.backup`을 보존한 뒤 자동 변환합니다. 사용량·선수·이름·사진을 유지하고, 기본 루키 9명을 한 번 지급합니다. 기존 누적 토큰에도 50M 기준을 적용합니다.

원본 AI 로그를 수정하지 않으며 대화 본문을 저장하거나 전송하지 않습니다.

```sh
swift test
swift run TokenBaseball --data-directory /tmp/tokenbaseball-demo
```

`--data-directory`는 테스트 데이터를 실제 진행 내용과 분리할 때 사용합니다. 생성된 앱은 로컬 개발용 서명이며 외부 배포용 공증은 별도입니다.

## 문서

- [앱 기획서](docs/앱-기획서.md)
- [기능 구현 목록](docs/기능-구현-목록.md)
- [개발 규칙](docs/개발-규칙.md)
- [검증 결과](docs/구현-검증-결과.md)
- [Codex 기록 형식](docs/codex-usage-format.md) · [Claude Code 기록 형식](docs/claude-usage-format.md)
