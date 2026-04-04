# Integration 프로토콜 — 외부 스킬 연동

> Phase 1 (Plan)에서 sub-team-lead 등 외부 스킬과 연동 시 로딩

## 개요

cmux-agent-teams는 독립 플러그인으로 단독 사용 가능하지만,
기존 Claude Code skill 생태계와도 연동할 수 있다.

## 독립 사용 (기본 모드)

외부 skill 없이도 완전히 동작한다:

```bash
# 1. 세션 초기화
SESSION=$(bash init-session.sh --cwd /path/to/project)
export CMUX_AGENT_SESSION=$SESSION

# 2. 에이전트 생성 (커스텀 역할)
AGENT_A=$(bash spawn-agent.sh --role "backend" --task "REST API 구현")
AGENT_B=$(bash spawn-agent.sh --role "frontend" --task "API 연동" --direction down)

# 3. 조율
bash wait-signal.sh --name "agent:${AGENT_A}:done"
bash send-message.sh --to "$AGENT_B" --type "task" \
  --payload '{"task_description":"Backend 완료. API 연동 시작"}' --signal

# 4. 정리
bash cleanup-session.sh --close-panes
```

## sub-team-lead 연동

sub-team-lead의 Phase 3 (Coordinate)에서 멀티 전문가 라우팅 시 cmux-agent-teams를 호출할 수 있다.

### 전제 조건

1. cmux가 설치되어 있어야 함 (`which cmux`)
2. cmux-agent-teams 플러그인이 로딩되어 있어야 함

### 호출 방식

sub-team-lead가 sister-skill invoke로 호출:

```xml
<sister-skill-invoke skill="cmux-agent-teams">
  <caller>sub-team-lead</caller>
  <phase>coordinate</phase>
  <trigger>multi-expert-parallel-via-cmux</trigger>
  <targets>{
    "pattern": "pipeline",
    "project_cwd": "/path/to/project",
    "agents": [
      {
        "role": "sub-api-designer",
        "task": "OpenAPI Spec 설계",
        "plugin_dir": "/path/to/plugins/sub-api-designer"
      },
      {
        "role": "sub-kopring-engineer",
        "task": "API Spec 기반 구현",
        "plugin_dir": "/path/to/plugins/sub-kopring-engineer",
        "depends_on": ["sub-api-designer"]
      },
      {
        "role": "sub-frontend-engineer",
        "task": "API 연동",
        "plugin_dir": "/path/to/plugins/sub-frontend-engineer",
        "depends_on": ["sub-kopring-engineer"]
      }
    ]
  }</targets>
  <constraints>
    <timeout>600s</timeout>
    <max-loop>1</max-loop>
  </constraints>
</sister-skill-invoke>
```

### 결과 반환

cmux-agent-teams는 실행 완료 후 sister-skill-result 형태로 결과를 반환:

```xml
<sister-skill-result skill="cmux-agent-teams">
  <status>completed</status>
  <summary>
    3 에이전트 Pipeline 실행 완료.
    - sub-api-designer: OpenAPI spec 생성 (openapi.yaml)
    - sub-kopring-engineer: 5 API endpoints 구현
    - sub-frontend-engineer: 5 API hooks 생성
  </summary>
  <artifacts>
    openapi.yaml
    src/main/kotlin/controllers/UserController.kt
    src/main/kotlin/services/UserService.kt
    frontend/src/hooks/useUsers.ts
    frontend/src/types/api.ts
  </artifacts>
  <metrics>
    total_duration: 180s
    agents: 3
    pattern: pipeline
  </metrics>
</sister-skill-result>
```

## 기존 Expert Skill과의 에이전트 연동

### Expert Skill을 에이전트로 실행

기존 expert skill (sub-kopring-engineer, sub-frontend-engineer 등)을 
cmux pane의 에이전트로 실행하려면 `--plugin-dir`을 지정:

```bash
spawn-agent.sh \
  --role "sub-kopring-engineer" \
  --task "UserService 구현" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer \
  --cwd /path/to/project
```

이 경우 해당 pane의 Claude Code 인스턴스는 sub-kopring-engineer skill의 
SKILL.md와 resources를 사용하면서, 추가로 IPC 시스템 프롬프트도 함께 적용된다.

### Expert Skill 없이 실행

`--plugin-dir` 없이 실행하면 일반 Claude Code가 커스텀 역할로 동작:

```bash
spawn-agent.sh \
  --role "backend-model" \
  --task "Entity 클래스 설계: User, Order" \
  --cwd /path/to/legacy-project
```

## cmux 사용 불가 시 Fallback

cmux가 설치되지 않은 환경에서는 기존 sister-skill invoke 방식을 사용:

```bash
if command -v cmux &>/dev/null; then
  # cmux 병렬 실행
  /cmux-agent-teams pipeline "..."
else
  # 기존 순차 sister-skill invoke
  # (sub-team-lead의 기본 coordinate 로직)
fi
```

## 환경 변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `CMUX_AGENT_SESSION` | 현재 세션 ID | (init-session.sh가 설정) |
| `CMUX_BIN` | cmux 바이너리 경로 | `cmux` |
| `CMUX_SURFACE_ID` | cmux가 자동 설정하는 현재 surface | (cmux 터미널 내 자동) |
| `CMUX_WORKSPACE_ID` | cmux가 자동 설정하는 현재 workspace | (cmux 터미널 내 자동) |
