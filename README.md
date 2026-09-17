# TokenBaseball

AI 토큰 사용 기록으로 재화를 얻고, 선수 카드를 수집해 야구단을 구성하는 macOS 앱입니다.

## 실행

macOS 14 이상과 Swift 6을 지원하는 Xcode/Command Line Tools가 필요합니다. 외부 패키지 의존성은 없습니다.

```sh
bash scripts/build-app.sh
open build/TokenBaseball.app
```

개발 중에는 `swift run TokenBaseball`로 실행할 수도 있습니다. Xcode에서 `Package.swift`를 열면 소스를 편집하고 실행할 수 있습니다.

## 개발 문서

- [기능 구현 목록](docs/기능-구현-목록.md)
- [개발 규칙과 초기 정책](docs/개발-규칙.md)

현재 앱 번들은 이 Mac에서 실행·검증하기 위한 개발용 서명입니다. 외부 배포용 서명·공증은 후속 작업입니다.
