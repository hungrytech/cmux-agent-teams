#!/usr/bin/env bash
# spawn-agent.sh — cmux pane에 Claude Code 에이전트 생성
#
# 사용법:
#   spawn-agent.sh --role <role-name> --task <task-description> \
#     [--direction right|down|left|up] \
#     [--cwd <project-dir>] \
#     [--plugin-dir <skill-dir>] \
#     [--session <session-id>] \
#     [--peers <agent-id-1,agent-id-2>] \
#     [--agent-id <custom-id>] \
#     [--timeout <seconds>] \
#     [--model <model-name>]
#
# 출력: agent-id (stdout)
#
# --role은 자유 텍스트:
#   - 기존 skill: "sub-kopring-engineer", "sub-frontend-engineer"
#   - 커스텀:     "backend-model", "database-migration", "api-client"
#
# --plugin-dir 미지정 시 일반 Claude Code로 실행 (레거시 프로젝트 호환)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq
require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
ROLE=""
TASK_DESC=""
DIRECTION="right"
PROJECT_CWD="${PWD}"
PLUGIN_DIR=""
SESSION_ID="$(get_session_id)"
PEERS=""
CUSTOM_AGENT_ID=""
TIMEOUT=300
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)       ROLE="$2"; shift 2 ;;
    --task)       TASK_DESC="$2"; shift 2 ;;
    --direction)  DIRECTION="$2"; shift 2 ;;
    --cwd)        PROJECT_CWD="$2"; shift 2 ;;
    --plugin-dir) PLUGIN_DIR="$2"; shift 2 ;;
    --session)    SESSION_ID="$2"; shift 2 ;;
    --peers)      PEERS="$2"; shift 2 ;;
    --agent-id)   CUSTOM_AGENT_ID="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --model)      MODEL="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

# ─── 유효성 검사 ─────────────────────────────────────
if [[ -z "$ROLE" ]]; then
  log_error "--role은 필수입니다"
  exit 1
fi

if [[ -z "$TASK_DESC" ]]; then
  log_error "--task는 필수입니다"
  exit 1
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID")"
if [[ ! -d "$IPC_DIR" ]]; then
  log_error "IPC 디렉터리가 없습니다: ${IPC_DIR}. init-session.sh를 먼저 실행하세요."
  exit 1
fi

# ─── 에이전트 ID 생성 ────────────────────────────────
AGENT_ID="${CUSTOM_AGENT_ID:-$(gen_agent_id "$ROLE")}"

# ─── cmux pane 생성 ──────────────────────────────────
log_info "Creating pane: direction=${DIRECTION}, role=${ROLE}"

SPLIT_OUTPUT="$(cmux_run new-split "$DIRECTION" 2>&1)"
# new-split 출력에서 surface ID 추출
SURFACE_ID="$(echo "$SPLIT_OUTPUT" | grep -oE 'surface:[0-9]+' | head -1 || echo "")"

if [[ -z "$SURFACE_ID" ]]; then
  # 출력 형태가 다를 수 있으므로 list-panes로 최신 surface 찾기
  sleep 0.5
  SURFACE_ID="$(cmux_run list-pane-surfaces 2>/dev/null | tail -1 | grep -oE 'surface:[0-9]+' | head -1 || echo "")"
fi

if [[ -z "$SURFACE_ID" ]]; then
  log_error "cmux pane 생성 실패. 출력: ${SPLIT_OUTPUT}"
  exit 1
fi

log_info "Pane created: surface=${SURFACE_ID}"

# ─── inbox 디렉터리 생성 ─────────────────────────────
mkdir -p "${IPC_DIR}/inbox/${AGENT_ID}"

# ─── 에이전트 등록 ───────────────────────────────────
REGISTRY_JSON=$(jq -n \
  --arg id "$AGENT_ID" \
  --arg role "$ROLE" \
  --arg surface_id "$SURFACE_ID" \
  --arg cwd "$PROJECT_CWD" \
  --arg peers "$PEERS" \
  --arg status "spawning" \
  --arg registered_at "$(iso_timestamp)" \
  --argjson timeout "$TIMEOUT" \
  '{
    id: $id,
    role: $role,
    surface_id: $surface_id,
    cwd: $cwd,
    peers: ($peers | split(",") | map(select(. != ""))),
    status: $status,
    registered_at: $registered_at,
    timeout_seconds: $timeout
  }')

atomic_write "${IPC_DIR}/registry/${AGENT_ID}.json" "$REGISTRY_JSON"

# ─── 작업 메시지를 inbox에 쓰기 ──────────────────────
TASK_MSG=$(jq -n \
  --arg id "$(gen_uuid)" \
  --arg type "task" \
  --arg from "orchestrator" \
  --arg to "$AGENT_ID" \
  --arg timestamp "$(iso_timestamp)" \
  --arg task_description "$TASK_DESC" \
  --arg project_root "$PROJECT_CWD" \
  --arg peers "$PEERS" \
  '{
    id: $id,
    type: $type,
    from: $from,
    to: $to,
    timestamp: $timestamp,
    payload: {
      task_description: $task_description,
      context: {
        project_root: $project_root,
        dependency_results: []
      },
      peers: ($peers | split(",") | map(select(. != ""))),
      artifacts: [],
      status: "pending"
    }
  }')

MSG_ID="$(echo "$TASK_MSG" | jq -r '.id')"
atomic_write "${IPC_DIR}/inbox/${AGENT_ID}/${MSG_ID}.json" "$TASK_MSG"

# ─── 에이전트 시스템 프롬프트 생성 ────────────────────
PROMPT_FILE="${IPC_DIR}/prompts/${AGENT_ID}.md"

# 프로젝트 컨텍스트 감지
PROJECT_CONTEXT=""
if [[ -f "${PROJECT_CWD}/CLAUDE.md" ]]; then
  PROJECT_CONTEXT="프로젝트에 CLAUDE.md가 있습니다. 참조하세요."
fi
if [[ -f "${PROJECT_CWD}/package.json" ]]; then
  PROJECT_CONTEXT="${PROJECT_CONTEXT}\nNode.js 프로젝트입니다 (package.json 존재)."
fi
if [[ -f "${PROJECT_CWD}/build.gradle" || -f "${PROJECT_CWD}/build.gradle.kts" ]]; then
  PROJECT_CONTEXT="${PROJECT_CONTEXT}\nGradle 프로젝트입니다."
fi
if [[ -f "${PROJECT_CWD}/pom.xml" ]]; then
  PROJECT_CONTEXT="${PROJECT_CONTEXT}\nMaven 프로젝트입니다."
fi
if [[ -f "${PROJECT_CWD}/go.mod" ]]; then
  PROJECT_CONTEXT="${PROJECT_CONTEXT}\nGo 프로젝트입니다."
fi
if [[ -f "${PROJECT_CWD}/requirements.txt" || -f "${PROJECT_CWD}/pyproject.toml" ]]; then
  PROJECT_CONTEXT="${PROJECT_CONTEXT}\nPython 프로젝트입니다."
fi

# peer 정보 생성
PEER_INSTRUCTIONS=""
if [[ -n "$PEERS" ]]; then
  PEER_INSTRUCTIONS="
## Peer-to-Peer 통신

당신은 다음 에이전트들과 직접 통신할 수 있습니다: ${PEERS}

### 다른 에이전트에게 메시지 보내기
\`\`\`bash
# 메시지 파일을 대상 에이전트의 inbox에 직접 작성
cat > ${IPC_DIR}/inbox/<target-agent-id>/<uuid>.json << 'MSGEOF'
{
  \"id\": \"<uuid>\",
  \"type\": \"peer-request\",
  \"from\": \"${AGENT_ID}\",
  \"to\": \"<target-agent-id>\",
  \"timestamp\": \"<iso-timestamp>\",
  \"payload\": {
    \"task_description\": \"요청 내용\",
    \"artifacts\": [\"파일 경로 목록\"],
    \"status\": \"pending\"
  }
}
MSGEOF

# 시그널 전송하여 알림
cmux wait-for -S \"${SESSION_ID}:agent:<target-agent-id>:peer-msg\"
\`\`\`

### 다른 에이전트의 결과 읽기
\`\`\`bash
# 대상 에이전트의 outbox 결과 파일 읽기
cat ${IPC_DIR}/outbox/<target-agent-id>.result.json
\`\`\`

### 다른 에이전트 발견하기
\`\`\`bash
# registry에서 다른 에이전트 목록 확인
ls ${IPC_DIR}/registry/
cat ${IPC_DIR}/registry/<agent-id>.json
\`\`\`
"
fi

cat > "$PROMPT_FILE" << PROMPT_EOF
# Agent Role: ${ROLE}
# Agent ID: ${AGENT_ID}
# Session: ${SESSION_ID}

## 당신의 역할
당신은 "${ROLE}" 역할을 수행하는 에이전트입니다.
프로젝트 디렉터리: ${PROJECT_CWD}
$(echo -e "$PROJECT_CONTEXT")

## IPC 프로토콜

당신은 멀티 에이전트 팀의 일원입니다. 아래 프로토콜을 따라주세요.

### 작업 읽기
작업 메시지는 다음 위치에 있습니다:
\`\`\`
${IPC_DIR}/inbox/${AGENT_ID}/
\`\`\`
JSON 파일을 읽어서 \`payload.task_description\`의 내용을 수행하세요.

### 결과 보고
작업이 완료되면 결과를 다음 위치에 JSON으로 작성하세요:
\`\`\`bash
cat > ${IPC_DIR}/outbox/${AGENT_ID}.result.json << 'EOF'
{
  "id": "<uuid>",
  "type": "result",
  "from": "${AGENT_ID}",
  "to": "orchestrator",
  "timestamp": "<현재시각>",
  "payload": {
    "status": "completed",
    "result_summary": "작업 결과 요약",
    "artifacts": ["생성/수정한 파일 경로 목록"],
    "metrics": {}
  }
}
EOF
\`\`\`

### 완료 시그널
결과를 작성한 후, 반드시 다음 명령으로 완료 시그널을 보내세요:
\`\`\`bash
cmux wait-for -S "${SESSION_ID}:agent:${AGENT_ID}:done"
\`\`\`

### 에러 발생 시
에러가 발생하면 result의 status를 "failed"로 설정하고 에러 시그널을 보내세요:
\`\`\`bash
cmux wait-for -S "${SESSION_ID}:agent:${AGENT_ID}:error"
\`\`\`
${PEER_INSTRUCTIONS}
## 중요 규칙
1. 작업 범위를 벗어나지 마세요
2. 결과 파일에는 생성/수정한 모든 파일 경로를 기록하세요
3. 작업 완료 후 반드시 완료 시그널을 보내세요
4. 타임아웃: ${TIMEOUT}초 내에 작업을 완료하세요
PROMPT_EOF

log_info "System prompt written: ${PROMPT_FILE}"

# ─── Claude Code 실행 ────────────────────────────────
CLAUDE_CMD="cd '${PROJECT_CWD}'"

# claude 명령 구성
CLAUDE_ARGS="-p --append-system-prompt-file '${PROMPT_FILE}'"

if [[ -n "$PLUGIN_DIR" ]]; then
  CLAUDE_ARGS="${CLAUDE_ARGS} --plugin-dir '${PLUGIN_DIR}'"
fi

if [[ -n "$MODEL" ]]; then
  CLAUDE_ARGS="${CLAUDE_ARGS} --model '${MODEL}'"
fi

CLAUDE_PROMPT="Read your task from ${IPC_DIR}/inbox/${AGENT_ID}/ and execute it. When done, write result to ${IPC_DIR}/outbox/${AGENT_ID}.result.json and run: cmux wait-for -S '${SESSION_ID}:agent:${AGENT_ID}:done'"

FULL_CMD="${CLAUDE_CMD} && claude ${CLAUDE_ARGS} '${CLAUDE_PROMPT}'"

log_info "Sending command to surface ${SURFACE_ID}"
cmux_run send --surface "$SURFACE_ID" "$FULL_CMD"
sleep 0.3
cmux_run send-key --surface "$SURFACE_ID" enter

# ─── registry 상태 업데이트 ──────────────────────────
jq '.status = "running"' "${IPC_DIR}/registry/${AGENT_ID}.json" > "${IPC_DIR}/registry/${AGENT_ID}.json.tmp"
mv "${IPC_DIR}/registry/${AGENT_ID}.json.tmp" "${IPC_DIR}/registry/${AGENT_ID}.json"

log_event "SPAWN" "Agent spawned: ${AGENT_ID} (role=${ROLE}, surface=${SURFACE_ID})"
log_info "Agent spawned: ${AGENT_ID}"

# stdout으로 agent-id 출력
echo "$AGENT_ID"
