# Claude Code 로컬 사용량 가져오기

`ClaudeUsageImporter().read(folder:)`는 Claude Code의 로컬 JSONL 세션에서 메시지별 누적 토큰 수를 반환한다. 기본 선택 위치는 `~/.claude`이다. `projects`, 개별 프로젝트 또는 하위 세션 폴더도 선택할 수 있다.

## 읽기 범위

- 선택한 폴더 안에 `projects`가 있으면 그 안의 `.jsonl`만 재귀적으로 읽는다. `.claude`에 `projects`가 아직 없으면 빈 결과를 반환한다.
- 프로젝트 하위의 서브에이전트 기록도 포함한다. `history.jsonl`, 숨김 파일, 심볼릭 링크 파일은 제외한다.
- 대화 본문은 저장하거나 출력하지 않는다. 파일을 한 줄씩 파싱하고 메시지 ID와 토큰 계수만 메모리에 유지한다. 인증 파일이나 API 키는 사용하지 않으며 네트워크 요청도 하지 않는다.
- 파일당 64 KiB씩 읽고 한 줄은 최대 64 MiB까지 허용한다. 이 제한을 넘거나 읽기 권한이 없으면 해당 가져오기 전체를 실패시킨다.

## 계산과 중복 방지

`type: "assistant"` 레코드의 `message.id`와 `message.usage`를 읽는다. `input_tokens`와 `output_tokens`는 필수이고, `cache_creation_input_tokens`와 `cache_read_input_tokens`가 없으면 각각 0으로 본다. `usage`가 없거나 `null`인 합성 알림은 제외한다.

```
totalTokens = input_tokens + output_tokens
            + cache_creation_input_tokens + cache_read_input_tokens
sourceID = "claude:" + message.id
```

`cache_creation` 안의 세부 계수는 상위 `cache_creation_input_tokens`의 내역이므로 다시 더하지 않는다. 같은 메시지 ID가 여러 줄·파일·스트리밍 갱신에 나타나면 네 계수 각각의 최댓값을 사용한다. 다시 가져와도 같은 `sourceID`를 반환하므로 앱은 이미 반영한 값보다 증가한 양만 지급할 수 있다.

계수는 0 이상 `Int64` 범위의 JSON 정수 리터럴만 허용한다. 문자열·불리언·소수·지수 표기는 거부한다. 큰 소수가 정수로 반올림되어 잘못 지급되지 않도록 Foundation의 부동소수점 숫자 표현도 거부한다. 계수 합산과 중복 병합 뒤 합산 모두 오버플로를 검사한다.

## 오류 처리와 한계

완성된 줄의 JSON이 손상되었거나 관련 사용량 필드가 잘못되어 있으면 전체 읽기를 실패시킨다. 마지막 줄에 줄바꿈이 없고 JSON 파싱이 실패한 경우에만 기록 도중인 줄로 보고 다음 동기화까지 보류한다. 줄바꿈이 없는 마지막 줄도 JSON이 완성되어 있으면 정상 처리하며, 완성된 JSON의 잘못된 계수는 오류다.

세션 폴더에 사용량이 없으면 빈 배열을 반환한다. 존재하지 않거나 읽을 수 없는 폴더는 오류다. 로컬 기록이 삭제되거나 세션 저장을 꺼 둔 경우 그 사용량은 복원할 수 없다. 이 값은 로컬 기록 기반 게임 재화 산정용이며 구독 잔여 한도나 청구 금액이 아니다. 파일 구조가 변경되면 파서를 갱신해야 한다.

## 근거

- [Claude Code 세션 문서](https://code.claude.com/docs/en/sessions): 로컬 세션은 `~/.claude/projects/<project>/<session-id>.jsonl`에 저장되며 `CLAUDE_CONFIG_DIR`로 위치를 변경할 수 있다.
- [Claude Agent SDK TypeScript 참조](https://code.claude.com/docs/en/agent-sdk/typescript): assistant 메시지의 `message`는 `id`와 `usage`를 포함하는 Anthropic 메시지이다. 이 구조를 로컬 세션 레코드에도 적용하며, 로컬 포맷의 영구 호환성은 가정하지 않는다.
- [Anthropic 프롬프트 캐싱 문서](https://platform.claude.com/docs/en/build-with-claude/prompt-caching): 총 입력 토큰은 일반 입력·캐시 생성·캐시 읽기 계수의 합이며, `cache_creation`은 캐시 생성 계수의 세부 내역이다.

자동 검증은 실제 대화가 없는 합성 JSONL로 중복, 스트리밍 증가, 캐시 계수, 서브에이전트, 잘못된 숫자, 오버플로, 부분 기록과 접근 실패를 검사한다.
