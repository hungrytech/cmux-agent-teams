# Spawn 프로토콜 — 에이전트 생성 라이프사이클

> Phase 2 (Spawn)에서 로딩

## 개요

에이전트 생성은 cmux pane 생성 → Claude Code 인스턴스 시작 → IPC 초기화를 포함한다.
어떤 프로젝트에서든 작동하도록 설계되었으며, 기존 expert skill이 없어도 커스텀 역할로 실행 가능하다.

## 생성 흐름

```
1. cmux new-split <direction>        → 새 터미널 pane 생성, surface ID 획득
2. mkdir inbox/{agent-id}/           → 에이전트 inbox 디렉터리 생성
3. write registry/{agent-id}.json    → 에이전트 등록 정보 기록
4. generate prompts/{agent-id}.md    → 시스템 프롬프트 생성 (IPC 안내 포함)
5. write inbox/{agent-id}/task.json  → 작업 메시지 배치
6. cmux send --surface <id> "..."    → Claude Code 실행 명령 전송
7. cmux send-key --surface <id> enter → 엔터키로 실행
8. (선택) wait-for :agent:{id}:ready → 에이전트 준비 대기
```

## spawn-agent.sh 인터페이스

### 필수 인자

| 인자 | 설명 | 예시 |
|------|------|------|
| `--role` | 에이전트 역할 (자유 텍스트) | `"sub-kopring-engineer"`, `"backend-model"` |
| `--task` | 작업 설명 (문자열) | `"Entity 클래스 설계: User, Order"` |

### 선택 인자

| 인자 | 기본값 | 설명 |
|------|--------|------|
| `--direction` | `right` | cmux split 방향 (right, down, left, up) |
| `--cwd` | 현재 디렉터리 | 에이전트 작업 디렉터리 |
| `--plugin-dir` | (없음) | Claude Code skill 플러그인 경로 |
| `--session` | `$CMUX_AGENT_SESSION` | 세션 ID |
| `--peers` | (없음) | P2P 통신 대상 (쉼표 구분) |
| `--agent-id` | 자동 생성 | 커스텀 에이전트 ID |
| `--timeout` | `300` | 타임아웃 (초) |
| `--model` | (없음) | Claude 모델 지정 |

### 출력

stdout으로 생성된 agent-id를 출력한다.

### 종료코드

| 코드 | 의미 |
|------|------|
| 0 | 성공 |
| 1 | 인자 오류 또는 IPC 디렉터리 없음 |
| 2 | cmux pane 생성 실패 |

## 역할 지정 방식

### 기존 Expert Skill 사용
```bash
spawn-agent.sh \
  --role "sub-kopring-engineer" \
  --task "User API 구현" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer
```

### 커스텀 역할 (skill 없이)
```bash
spawn-agent.sh \
  --role "backend-model" \
  --task "Entity 클래스 설계: User, Order, Payment"
```

### 레거시 프로젝트에 적용
```bash
spawn-agent.sh \
  --role "database-migration" \
  --task "Flyway 마이그레이션 스크립트 작성" \
  --cwd /path/to/legacy-project
```

## 프로젝트 컨텍스트 자동 감지

spawn-agent.sh는 `--cwd` 디렉터리에서 다음 파일을 자동 감지하여 에이전트 시스템 프롬프트에 포함:

| 파일 | 감지 내용 |
|------|-----------|
| `CLAUDE.md` | Claude Code 프로젝트 설정 |
| `package.json` | Node.js 프로젝트 |
| `build.gradle(.kts)` | Gradle 프로젝트 |
| `pom.xml` | Maven 프로젝트 |
| `go.mod` | Go 프로젝트 |
| `requirements.txt` / `pyproject.toml` | Python 프로젝트 |

## Pane 배치 전략

에이전트 수에 따른 권장 pane 배치:

```
2 에이전트:
┌──────────┬──────────┐
│ Orch     │ Agent-A  │
│          │          │
│          ├──────────┤
│          │ Agent-B  │
└──────────┴──────────┘

3 에이전트:
┌──────┬──────┬──────┐
│ Orch │ A    │ B    │
│      │      │      │
│      │      ├──────┤
│      │      │ C    │
└──────┴──────┴──────┘

4+ 에이전트:
새 workspace 생성 고려 (cmux new-workspace)
```

## 시스템 프롬프트 구성

에이전트에 주입되는 시스템 프롬프트는 다음으로 구성:

1. **역할 정의** — 에이전트가 수행할 역할
2. **IPC 안내** — inbox/outbox 경로, 시그널 사용법
3. **P2P 통신 안내** — peers 지정 시 포함
4. **프로젝트 컨텍스트** — 자동 감지된 프로젝트 정보
5. **제약 사항** — 타임아웃, 작업 범위 규칙

## 최대 에이전트 수

기본 6개. session.json의 `config.max_agents`로 조정 가능.
cmux 터미널 공간과 시스템 리소스를 고려하여 설정.
