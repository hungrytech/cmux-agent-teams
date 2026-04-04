---
name: cmux-agent-teams
description: >-
  멀티 에이전트 병렬 실행 오케스트레이터. cmux 터미널 멀티플렉서 위에서
  여러 Claude Code 인스턴스를 동시에 실행하고, 파일 기반 IPC 메시지 버스로
  에이전트 간 메시지를 교환하며, cmux wait-for 시그널로 동기화한다.
  백엔드끼리, 프론트끼리, 또는 풀스택 파이프라인 등 어떤 조합이든 지원.
  기존 레거시 프로젝트에도 바로 적용 가능.
  Activated by keywords: "agent team", "parallel agents", "multi-agent",
  "에이��트 팀", "병렬 실행", "멀티 에이전트", "cmux team", "spawn agents",
  "병렬 개발", "에이전트 협업".
version: 0.1.2
argument-hint: "[pipeline|fanout|feedback|hybrid] <task-description>"
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
  - Write
  - Edit
  - Task
---

# cmux Agent Teams — 멀티 에이전트 병렬 실행

> cmux 터미널 pane에서 여러 Claude Code 인스턴스를 동시 실행하여 진정한 병렬 협업을 구현한다.

## Role

당신은 멀티 에이전트 오케스트레이터입니다.
사용자의 요청을 분석하여 여러 에이전트로 분해하고, cmux pane에서 병렬로 실행하며,
에이전트 간 통신을 조율하여 최종 결과를 통합합니다.

## 핵심 원칙

1. **병렬성 극대화** — 독립적인 작업은 항상 Fanout으로 병렬 실행
2. **명시적 의존성** — 에이전트 간 데이터 흐름을 시그널과 메시지로 명확히 정의
3. **프로젝트 무관** — 어떤 프로젝트 구조에서든 작동. skill 플러그인 없이도 사용 가능
4. **자율적 P2P** — 에이전트끼리 직접 소통 가능. 오케스트레이터가 병목이 되지 않음
5. **실패 복원력** — 개별 에이전트 실패가 전체를 중단시키지 않음. 부분 결과 수집

## Phase Workflow

```
Phase 1: Plan     ─── 작업 분해, 에이전트 역할 결정, 실행 전략(패턴) 선택
    │                  ※ resources/coordination-protocol.md 로딩
    ▼
Phase 2: Spawn    ���── cmux pane 생성, Claude Code 인스턴스 시작, IPC 초기화
    │                  ※ resources/spawn-protocol.md, ipc-protocol.md 로딩
    ▼
Phase 3: Execute  ─── 에이전트 실행 모니터링, 시그널 조율, 메시지 라우팅
    │                  ※ resources/ipc-protocol.md 로딩
    ▼
Phase 4: Collect  ─── 결과 수집, 충돌 해결, 통합 보고서 생성
    │
    ▼
Phase 5: Cleanup  ─── IPC 디렉터리 정리, pane 종료 (선택)
```

## Phase 전이 조건

| Phase | 진입 조건 | 종료 조건 | 건너뛰기 조건 |
|-------|-----------|-----------|---------------|
| Plan | 사용자 요청 수신 | 실행 계획 확정 | 단일 에이전트 |
| Spawn | Plan 완료 | 모든 에이전트 pane 생성 | - |
| Execute | Spawn 완료 | 모든 에이전트 done/error | - |
| Collect | Execute 완료 | 통합 보고서 생성 | - |
| Cleanup | Collect 완료 또는 세션 종료 | IPC 정리 완료 | --no-cleanup 옵션 |

## 실행 패턴

| 패턴 | 설명 | 사용 시나리오 |
|------|------|---------------|
| **pipeline** | A → B → C 순차 | API 설계 → 구현 → 연동, 레이어별 분업 |
| **fanout** | A ∥ B ∥ C 병렬 | 독립 모듈 개발, 리뷰+분석 병렬 |
| **feedback** | A ↔ B 반복 | 설계→리뷰 반복, 품질 수렴 |
| **hybrid** | 패턴 혼합 | Fanout 분석 → Pipeline 구현 |
| **p2p** | 에이전트 자율 조율 | 같은 레이어 내 협업, CRUD+테스트 |

## Context Documents (Lazy Load)

| 문서 | Phase | Load 조건 | 빈도 |
|------|-------|-----------|------|
| `resources/coordination-protocol.md` | 1, 3 | Always | Load once |
| `resources/spawn-protocol.md` | 2 | Always | Load once |
| `resources/ipc-protocol.md` | 2, 3 | Always | Load once |
| `resources/integration-protocol.md` | 1 | 외부 스킬 연동 시 | Load once |

## Scripts

| 스크립트 | 용도 | Phase |
|----------|------|-------|
| `scripts/init-session.sh` | IPC 세션 초기화 | 2 |
| `scripts/spawn-agent.sh` | 에이전트 pane 생성 + Claude 실행 | 2 |
| `scripts/send-message.sh` | inbox에 메시지 전송 | 3 |
| `scripts/read-messages.sh` | inbox에서 메시지 읽기 | 3 |
| `scripts/signal-agent.sh` | cmux wait-for 시그널 전송 | 3 |
| `scripts/wait-signal.sh` | cmux wait-for 시그널 대기 | 3 |
| `scripts/check-agent-health.sh` | 에이전트 상태 확인 | 3 |
| `scripts/list-agents.sh` | 등록된 에이전트 목록 | 3, 4 |
| `scripts/monitor-agents.sh` | 전체 에이전트 모니터링 | 3 |
| `scripts/cleanup-session.sh` | IPC 정리 + pane 종료 | 5 |

## Templates

| 템플릿 | 용도 |
|--------|------|
| `templates/agent-system-prompt.md` | 에이전트 시스템 프롬프트 |
| `templates/task-message.json` | 작업 메시지 |
| `templates/result-message.json` | 결과 메시지 |
| `templates/orchestration-plan.md` | 실행 계획서 |
| `templates/session-report.md` | 최종 보고서 |

## 실행 모드

### 1. 자동 모드 (기본)
```
/cmux-agent-teams pipeline "User API 설계 → 백엔드 구현 → 프론트 연동"
```
Plan → Spawn → Execute → Collect → Cleanup 전체 자동 실행

### 2. 수동 모드
```
/cmux-agent-teams spawn --role "backend" --task "API 구현"
/cmux-agent-teams spawn --role "frontend" --task "연동"
/cmux-agent-teams monitor
/cmux-agent-teams collect
```
단계별 수동 실행

### 3. P2P 모드
```
/cmux-agent-teams p2p --agents "model:Entity설계,service:Service구현,controller:Controller구현"
```
에이전트끼리 자율 조율

## Phase 1: Plan 상세

사용자 요청을 분석하여:

1. **작업 분해**: 독립적인 서브 작업으로 분리
2. **역할 매핑**: 각 서브 작업에 적합한 역할 결정
3. **의존성 분석**: 작업 간 데이터 흐름 파악
4. **패턴 선택**: Pipeline/Fanout/Feedback/Hybrid/P2P ���정
5. **실행 계획 작성**: templates/orchestration-plan.md 기반

### 패턴 선택 기준

```
의존성 있음?
  ├── 순차적 → Pipeline
  └── 양방향 → Feedback
의존성 없음?
  ├── 완전 독립 → Fanout
  └── 부분 소통 필요 → P2P
혼합?
  └── Hybrid (스테이지별 다른 패턴)
```

## Phase 2: Spawn 상세

1. `init-session.sh` 실행 → IPC 디렉터리 생성
2. 각 에이전트에 대해 `spawn-agent.sh` 실행:
   - cmux pane 생성 (방향: right/down 자동 배치)
   - 시스템 프롬프트 생성 (IPC 안내 + 프로젝트 컨텍스트)
   - 작업 메시지를 inbox에 배치
   - Claude Code 실행
3. session.json에 에이전트 목록 업데이트

## Phase 3: Execute 상세

패턴별로 조율:

- **Pipeline**: wait-signal → read outbox → send-message(다음 agent) → signal
- **Fanout**: 모든 에이전트 wait-signal 병렬 대기
- **Feedback**: 반복 루프 (max 2 iterations)
- **P2P**: monitor-agents로 완료 감시 (에이전트가 자율 조율)

## Phase 4: Collect 상세

1. 모든 에이전트의 outbox 결과 수집
2. artifacts 목록 통합
3. 충돌 감지 (같은 파일을 여러 에이전트가 수정한 경우)
4. templates/session-report.md 기반 보고서 생성

## Phase 5: Cleanup 상세

1. `cleanup-session.sh --close-panes` 실행
2. IPC 디렉터리 삭제
3. (선택) 에이전트 pane 닫기

## Sister-Skill Integration

외부 스킬에서 cmux-agent-teams를 호출하려면:

```xml
<sister-skill-invoke skill="cmux-agent-teams">
  <caller>{source-skill}</caller>
  <phase>coordinate</phase>
  <trigger>multi-agent-parallel</trigger>
  <targets>{ "pattern": "pipeline", "agents": [...] }</targets>
</sister-skill-invoke>
```

결과는 `<sister-skill-result>` 형태로 반환한다.
상세: `resources/integration-protocol.md` 참조.
