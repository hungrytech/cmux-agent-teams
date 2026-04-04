# IPC 프로토콜 — 파일 기반 메시지 버스

> Phase 2 (Spawn), Phase 3 (Execute)에서 로딩

## 개요

cmux-agent-teams의 에이전트 간 통신은 **파일 기반 IPC**와 **cmux wait-for 시그널**을 조합하여 구현한다.
cmux buffer는 paste-only라 프로그래밍 방식의 읽기가 불편하므로, `/tmp/` 파일 시스템을 메시지 버스로 사용한다.

## 디렉터리 구조

```
/tmp/cmux-agent-ipc/{session-id}/
├── session.json                    # 세션 메타데이터
├── events.log                      # 이벤트 로그
├── cmux-debug.log                  # cmux 명령 디버그 로그
│
├── registry/                       # 에이전트 등록 정보
│   ├── {agent-id-1}.json
│   ├── {agent-id-2}.json
│   └── ...
│
├── inbox/                          # 에이전트별 수신 메시지 큐
│   ├── orchestrator/               # 오케스트레이터 inbox
│   │   └── {msg-uuid}.json
│   ├── {agent-id-1}/
│   │   ├── {msg-uuid}.json
│   │   └── .consumed/             # 처리 완료된 메시지
│   └── {agent-id-2}/
│       └── ...
│
├── outbox/                         # 완료 결과
│   ├── {agent-id-1}.result.json
│   └── {agent-id-2}.result.json
│
├── prompts/                        # 에이전트 시스템 프롬프트
│   ├── {agent-id-1}.md
│   └── {agent-id-2}.md
│
└── signals/                        # 시그널 로그
    └── signal.log
```

## 메시지 JSON 포맷

### 필드 정의

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `id` | string (UUID) | O | 메시지 고유 식별자 |
| `type` | string | O | 메시지 유형 (아래 참조) |
| `from` | string | O | 발신자 (agent-id 또는 "orchestrator") |
| `to` | string | O | 수신자 (agent-id, "orchestrator", "broadcast") |
| `timestamp` | string (ISO-8601) | O | 메시지 생성 시각 (UTC) |
| `payload` | object | O | 메시지 본문 |
| `metadata` | object | - | 부가 정보 (session_id, sequence, reply_to 등) |

### 메시지 유형 (type)

| type | 방향 | 설명 |
|------|------|------|
| `task` | orchestrator → agent | 작업 할당 |
| `result` | agent → orchestrator | 작업 완료 결과 |
| `signal` | any → any | 상태 변경 알림 |
| `error` | agent → orchestrator | 에러 보고 |
| `peer-request` | agent → agent | P2P 작업 요청 |
| `peer-response` | agent → agent | P2P 요청에 대한 응답 |

### payload 필드 (type별)

**task:**
```json
{
  "task_description": "수행할 작업 설명",
  "context": {
    "project_root": "/path/to/project",
    "dependency_results": [
      {
        "agent_id": "이전-agent-id",
        "summary": "이전 에이전트 결과 요약",
        "artifacts": ["파일 경로"]
      }
    ],
    "constraints": "제약 사항"
  },
  "peers": ["peer-agent-id-1", "peer-agent-id-2"],
  "artifacts": [],
  "status": "pending",
  "timeout_seconds": 300
}
```

**result:**
```json
{
  "status": "completed|partial|failed",
  "result_summary": "작업 결과 요약",
  "artifacts": ["/absolute/path/to/file1", "/absolute/path/to/file2"],
  "metrics": {
    "files_created": 3,
    "files_modified": 1,
    "duration_seconds": 45
  },
  "error": null
}
```

**peer-request / peer-response:**
```json
{
  "task_description": "요청 내용",
  "artifacts": ["참조할 파일 경로"],
  "status": "pending|completed",
  "reply_to": "원본 peer-request의 id (response일 때)"
}
```

## 시그널 네이밍 컨벤션

모든 시그널은 세션 ID로 prefix되어 세션 간 충돌을 방지한다.

| 시그널 패턴 | 설명 | 발신자 |
|-------------|------|--------|
| `{session}:agent:{id}:ready` | 에이전트 초기화 완료 | 에이전트 |
| `{session}:agent:{id}:done` | 작업 완료 | 에이전트 |
| `{session}:agent:{id}:error` | 에러 발생 | 에이전트 |
| `{session}:agent:{id}:peer-msg` | P2P 메시지 도착 | 발신 에이전트 |
| `{session}:stage:{name}:done` | 파이프라인 스테이지 완료 | 오케스트레이터 |
| `{session}:all-done` | 전체 에이전트 완료 | 모니터 |

## 원자적 쓰기

레이스 컨디션 방지를 위해 모든 파일 쓰기는 **원자적**으로 수행:

```bash
# 1. 임시 파일에 쓰기
echo "$content" > "${target}.tmp.$$"
# 2. 원자적 이동
mv "${target}.tmp.$$" "$target"
```

`mv`는 같은 파일 시스템 내에서 원자적으로 동작한다.

## 통신 모드

### 1. Orchestrated (기본)
```
Agent-A → outbox → Orchestrator → inbox → Agent-B
```
오케스트레이터가 모든 메시지를 중개. 안전하지만 오케스트레이터가 병목이 될 수 있음.

### 2. Peer-to-Peer
```
Agent-A → inbox/Agent-B/ (직접 쓰기)
Agent-A → cmux wait-for -S (시그널 알림)
```
에이전트가 직접 다른 에이전트의 inbox에 메시지를 쓰고 시그널로 알림.
오케스트레이터 없이 빠르게 통신 가능.

### 3. Broadcast
```
Agent-A → inbox/모든-에이전트/ (전체 복사)
```
`to: "broadcast"` 메시지는 registry의 모든 에이전트 inbox에 복사됨.

## 에이전트 등록 (Registry)

```json
{
  "id": "backend-model-a1b2c3d4",
  "role": "backend-model",
  "surface_id": "surface:2",
  "cwd": "/path/to/project",
  "peers": ["backend-service-e5f6g7h8"],
  "status": "running",
  "registered_at": "2026-04-04T10:30:00Z",
  "timeout_seconds": 300
}
```

### status 전이

```
spawning → running → completed
                   → failed
```
