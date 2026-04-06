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
#     [--model <model-name>] \
#     [--sub-agents]
#
# --direction: 수동 분할 방향 지정 (생략 시 자동 그리드 레이아웃)
#   자동 그리드 레이아웃 (행당 최대 3개):
#     - 첫 번째 에이전트: 위(up)로 분할 → 오케스트레이터가 하단 고정
#     - 같은 행 추가: 이전 에이전트 오른쪽(right)으로 분할
#     - 새 행 시작(4번째, 7번째...): 이전 행 첫 에이전트 아래(down)로 분할
#     ┌─────────┬─────────┬─────────┐
#     │ Agent-1 │ Agent-2 │ Agent-3 │  row 0
#     ├─────────┼─────────┼─────────┤
#     │ Agent-4 │ Agent-5 │ Agent-6 │  row 1
#     ├─────────┴─────────┴─────────┤
#     │      Orchestrator (하단)     │
#     └─────────────────────────────┘
#
# --sub-agents: 에이전트가 내부적으로 더 작은 서브에이전트를 스폰할 수 있도록 허용
#               (teammateMode: in-process, Agent 도구 활성화)
#               기본값: off (서브에이전트 없이 단독 실행)
#
# Pane 재활용 (자동):
#   Stage 전환 시 reset-grid-cursor.sh를 호출하면,
#   다음 spawn-agent.sh 호출 시 기존 pane을 자동으로 재활용한다.
#   기존 pane이 모두 소진되면 자동으로 새 pane 생성 (그리드 확장)
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
DIRECTION=""
PROJECT_CWD="${PWD}"
PLUGIN_DIR=""
SESSION_ID="$(get_session_id)"
PEERS=""
CUSTOM_AGENT_ID=""
TIMEOUT=300
MODEL=""
SUB_AGENTS=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)        ROLE="$2"; shift 2 ;;
    --task)        TASK_DESC="$2"; shift 2 ;;
    --direction)   DIRECTION="$2"; shift 2 ;;
    --cwd)         PROJECT_CWD="$2"; shift 2 ;;
    --plugin-dir)  PLUGIN_DIR="$2"; shift 2 ;;
    --session)     SESSION_ID="$2"; shift 2 ;;
    --peers)       PEERS="$2"; shift 2 ;;
    --agent-id)    CUSTOM_AGENT_ID="$2"; shift 2 ;;
    --timeout)     TIMEOUT="$2"; shift 2 ;;
    --model)       MODEL="$2"; shift 2 ;;
    --sub-agents)  SUB_AGENTS=true; shift ;;
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

# ─── inbox 디렉터리 생성 ─────────────────────────────
mkdir -p "${IPC_DIR}/inbox/${AGENT_ID}"

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

# 서브에이전트 안내 (--sub-agents 옵션에 따라)
SUB_AGENT_INSTRUCTIONS=""
if [[ "$SUB_AGENTS" == true ]]; then
  SUB_AGENT_INSTRUCTIONS="
## 서브에이전트 활용
작업이 복잡한 경우 Agent 도구로 서브에이전트를 생성하여 병렬로 작업을 분할할 수 있습니다.
예: 파일 생성은 서브에이전트에게 위임하고, 메인 작업은 직접 수행.
teammateMode가 in-process로 설정되어 있어 서브에이전트가 이 터미널 내에서 실행됩니다.
작업이 크면 Agent 도구로 서브에이전트를 적극 활용하세요.
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
${SUB_AGENT_INSTRUCTIONS}
## 중요 규칙 (반드시 따르세요)
1. 작업 시작 전에 먼저 inbox의 JSON 파일을 읽어서 task_description을 확인하세요
2. 작업 범위를 벗어나지 마세요
3. 결과 파일에는 생성/수정한 모든 파일 경로를 기록하세요
4. 타임아웃: ${TIMEOUT}초 내에 작업을 완료하세요

## !! 작업 완료 시 반드시 실행할 것 (가장 중요) !!
작업이 모두 끝나면 **반드시** 아래 두 명령을 Bash 도구로 **순서대로** 실행하세요:

**Step 1**: result JSON 파일 작성
\`\`\`bash
cat > ${IPC_DIR}/outbox/${AGENT_ID}.result.json << 'RESULTEOF'
{
  "id": "result-1",
  "type": "result",
  "from": "${AGENT_ID}",
  "to": "orchestrator",
  "payload": {
    "status": "completed",
    "result_summary": "여기에 작업 결과 요약 작성",
    "artifacts": ["생성한 파일 경로들"]
  }
}
RESULTEOF
\`\`\`

**Step 2**: 완료 시그널 전송
\`\`\`bash
cmux wait-for -S "${SESSION_ID}:agent:${AGENT_ID}:done"
\`\`\`

이 두 단계를 실행하지 않으면 오케스트레이터가 영원히 대기합니다.
PROMPT_EOF

log_info "System prompt written: ${PROMPT_FILE}"

# ─── 런처 스크립트 생성 ──────────────────────────────
# cmux send의 따옴표 문제를 피하기 위해 실행 스크립트를 파일로 생성
LAUNCHER="${IPC_DIR}/prompts/${AGENT_ID}.launcher.sh"

# 에이전트 설정 JSON 생성
AGENT_SETTINGS="${IPC_DIR}/prompts/${AGENT_ID}.settings.json"
if [[ "$SUB_AGENTS" == true ]]; then
  # --sub-agents: 서브에이전트 스폰 허용 (teammateMode: in-process)
  cat > "$AGENT_SETTINGS" << SETTINGS_EOF
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process",
  "permissions": {
    "allow": ["Agent", "Bash", "Read", "Write", "Edit", "Glob", "Grep"]
  }
}
SETTINGS_EOF
  log_info "Sub-agents enabled for ${AGENT_ID}"
else
  # 기본: 서브에이전트 없이 단독 실행
  cat > "$AGENT_SETTINGS" << SETTINGS_EOF
{
  "permissions": {
    "allow": ["Bash", "Read", "Write", "Edit", "Glob", "Grep"]
  }
}
SETTINGS_EOF
fi

# claude 명령 인자 조립
CLAUDE_OPTS="--dangerously-skip-permissions --append-system-prompt-file ${PROMPT_FILE} --settings ${AGENT_SETTINGS}"
if [[ -n "$PLUGIN_DIR" ]]; then
  CLAUDE_OPTS="${CLAUDE_OPTS} --plugin-dir ${PLUGIN_DIR}"
fi
if [[ -n "$MODEL" ]]; then
  CLAUDE_OPTS="${CLAUDE_OPTS} --model ${MODEL}"
fi

CLAUDE_PROMPT="Read the task JSON from ${IPC_DIR}/inbox/${AGENT_ID}/ and execute the task_description. When finished, write your result JSON to ${IPC_DIR}/outbox/${AGENT_ID}.result.json and then run this exact Bash command: cmux wait-for -S ${SESSION_ID}:agent:${AGENT_ID}:done"

# 런처 스크립트 생성
{
  echo '#!/usr/bin/env bash'
  echo ""
  echo "cd '${PROJECT_CWD}'"
  echo ""
  echo "# 백그라운드 모니터: outbox에 결과 파일이 생기면 자동으로 시그널 전송"
  echo "("
  echo "  while [ ! -f '${IPC_DIR}/outbox/${AGENT_ID}.result.json' ]; do"
  echo "    sleep 3"
  echo "  done"
  echo "  sleep 2"
  echo "  cmux wait-for -S '${SESSION_ID}:agent:${AGENT_ID}:done' 2>/dev/null || true"
  echo ") &"
  echo "MONITOR_PID=\$!"
  echo ""
  echo "# 대화형 모드: 전체 Claude Code TUI가 그대로 보임"
  echo "claude --dangerously-skip-permissions --append-system-prompt-file '${PROMPT_FILE}' '${CLAUDE_PROMPT}'"
  echo ""
  echo "# Claude 종료 시 (사용자가 /exit 등으로 나간 경우) fallback"
  echo "kill \$MONITOR_PID 2>/dev/null || true"
  echo "if [ ! -f '${IPC_DIR}/outbox/${AGENT_ID}.result.json' ]; then"
  echo "  TIMESTAMP=\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "  printf '{\"id\":\"auto\",\"type\":\"result\",\"from\":\"${AGENT_ID}\",\"to\":\"orchestrator\",\"timestamp\":\"%s\",\"payload\":{\"status\":\"completed\",\"result_summary\":\"Agent completed (auto-result)\",\"artifacts\":[],\"metrics\":{}}}' \"\$TIMESTAMP\" > '${IPC_DIR}/outbox/${AGENT_ID}.result.json'"
  echo "fi"
  echo "cmux wait-for -S '${SESSION_ID}:agent:${AGENT_ID}:done' 2>/dev/null || true"
} > "$LAUNCHER"

chmod +x "$LAUNCHER"
log_info "Launcher script written: ${LAUNCHER}"

# ─── cmux 분할 창에서 런처 실행 ────────────────────────
# 그리드 레이아웃 전략:
#   - 행당 최대 3개 에이전트 (MAX_COLS=3)
#   - 첫 번째 에이전트: 오케스트레이터 위로 분할 (up)
#   - 같은 행 추가: 이전 에이전트 오른쪽으로 분할 (right)
#   - 새 행 시작: 이전 행 첫 번째 에이전트 아래로 분할 (down)
#   - 오케스트레이터는 항상 하단 고정
#
# 결과 레이아웃 (6개 에이전트 예시):
#   ┌─────────┬─────────┬─────────┐
#   │ Agent-1 │ Agent-2 │ Agent-3 │  ← row 0
#   ├─────────┼─────────┼─────────┤
#   │ Agent-4 │ Agent-5 │ Agent-6 │  ← row 1
#   ├─────────┴─────────┴─────────┤
#   │      Orchestrator (하단)     │
#   └─────────────────────────────┘

MAX_COLS=3
GRID_FILE="${IPC_DIR}/.agent-grid.json"

# 그리드 상태 초기화 또는 읽기
if [[ ! -f "$GRID_FILE" ]]; then
  echo '{"count":0,"grid":[],"reuse_cursor":0}' > "$GRID_FILE"
fi

# reuse_cursor 필드가 없으면 추가 (기존 grid 호환)
if [[ "$(jq 'has("reuse_cursor")' "$GRID_FILE")" != "true" ]]; then
  jq '.reuse_cursor = 0' "$GRID_FILE" > "${GRID_FILE}.tmp" && mv "${GRID_FILE}.tmp" "$GRID_FILE"
fi

GRID_COUNT=$(jq -r '.count' "$GRID_FILE")
GRID_ROW=$((GRID_COUNT / MAX_COLS))
GRID_COL=$((GRID_COUNT % MAX_COLS))

extract_surface() {
  local output="$1"
  echo "$output" | grep -oE 'surface:[0-9]+' | head -1 || echo ""
}

fallback_surface() {
  sleep 0.5
  cmux_run tree 2>/dev/null | grep 'surface:' | tail -1 | grep -oE 'surface:[0-9]+' | head -1 || echo "unknown"
}

REUSED_PANE=false

# ─── 자동 pane 재활용 ──────────────────────────────────
# reuse_cursor가 기존 grid 항목 수보다 작으면 기존 pane을 재활용.
# Stage A에서 3개 pane 생성 → reset-grid-cursor.sh 호출 →
# Stage B에서 자동으로 기존 3개 pane을 순서대로 재활용.
# 기존 pane이 모두 소진되면 새 pane을 생성 (그리드 확장).

REUSE_CURSOR=$(jq -r '.reuse_cursor' "$GRID_FILE")
GRID_TOTAL=$(jq -r '.grid | length' "$GRID_FILE")

if [[ $REUSE_CURSOR -lt $GRID_TOTAL ]]; then
  # 기존 pane 재활용
  SURFACE_ID=$(jq -r ".grid[${REUSE_CURSOR}].surface" "$GRID_FILE")
  REUSE_ROW=$(jq -r ".grid[${REUSE_CURSOR}].row" "$GRID_FILE")
  REUSE_COL=$(jq -r ".grid[${REUSE_CURSOR}].col" "$GRID_FILE")
  log_info "Reusing pane (cursor=${REUSE_CURSOR}, surface=${SURFACE_ID}): row=${REUSE_ROW}, col=${REUSE_COL}, agent=${AGENT_ID}"

  # grid 항목을 새 에이전트로 갱신, cursor 전진
  jq --argjson idx "$REUSE_CURSOR" \
     --arg agent_id "$AGENT_ID" \
     '.grid[$idx].agent_id = $agent_id | .reuse_cursor += 1' \
     "$GRID_FILE" > "${GRID_FILE}.tmp" && mv "${GRID_FILE}.tmp" "$GRID_FILE"

  REUSED_PANE=true
fi

if [[ "$REUSED_PANE" != true ]]; then
  # ─── 새 pane 생성 (일반 그리드 레이아웃) ────────────────

  if [[ -n "$DIRECTION" ]]; then
    # 수동 모드: --direction이 명시적으로 지정된 경우 그대로 사용
    log_info "Creating split pane (manual): direction=${DIRECTION}, agent=${AGENT_ID}"
    SPLIT_OUTPUT="$(cmux_run new-split "$DIRECTION" 2>&1)"
    SURFACE_ID="$(extract_surface "$SPLIT_OUTPUT")"
    [[ -z "$SURFACE_ID" ]] && SURFACE_ID="$(fallback_surface)"

  elif [[ $GRID_COUNT -eq 0 ]]; then
    # 첫 번째 에이전트: 위로 분할 (오케스트레이터 하단 고정)
    log_info "Creating first agent pane (up): row=0, col=0, agent=${AGENT_ID}"
    SPLIT_OUTPUT="$(cmux_run new-split up 2>&1)"
    SURFACE_ID="$(extract_surface "$SPLIT_OUTPUT")"
    [[ -z "$SURFACE_ID" ]] && SURFACE_ID="$(fallback_surface)"

  elif [[ $GRID_COL -eq 0 ]]; then
    # 새 행 시작: 이전 행의 첫 번째 에이전트 아래로 분할
    PREV_ROW=$((GRID_ROW - 1))
    PREV_ROW_FIRST=$(jq -r ".grid[] | select(.row == ${PREV_ROW} and .col == 0) | .surface" "$GRID_FILE")
    log_info "Creating new row (down from ${PREV_ROW_FIRST}): row=${GRID_ROW}, col=0, agent=${AGENT_ID}"
    SPLIT_OUTPUT="$(cmux_run new-split down --surface "$PREV_ROW_FIRST" 2>&1)"
    SURFACE_ID="$(extract_surface "$SPLIT_OUTPUT")"
    [[ -z "$SURFACE_ID" ]] && SURFACE_ID="$(fallback_surface)"

  else
    # 같은 행 추가: 직전 에이전트 오른쪽으로 분할
    PREV_COL=$((GRID_COL - 1))
    PREV_SURFACE=$(jq -r ".grid[] | select(.row == ${GRID_ROW} and .col == ${PREV_COL}) | .surface" "$GRID_FILE")
    log_info "Creating agent pane (right of ${PREV_SURFACE}): row=${GRID_ROW}, col=${GRID_COL}, agent=${AGENT_ID}"
    SPLIT_OUTPUT="$(cmux_run new-split right --surface "$PREV_SURFACE" 2>&1)"
    SURFACE_ID="$(extract_surface "$SPLIT_OUTPUT")"
    [[ -z "$SURFACE_ID" ]] && SURFACE_ID="$(fallback_surface)"
  fi

  # 그리드 상태 업데이트 (새 pane 추가)
  jq --arg surface "$SURFACE_ID" \
     --argjson row "$GRID_ROW" \
     --argjson col "$GRID_COL" \
     --arg agent_id "$AGENT_ID" \
     '.count += 1 | .grid += [{"surface": $surface, "row": $row, "col": $col, "agent_id": $agent_id}]' \
     "$GRID_FILE" > "${GRID_FILE}.tmp" && mv "${GRID_FILE}.tmp" "$GRID_FILE"
fi

log_info "Pane ready: surface=${SURFACE_ID} (reused=${REUSED_PANE})"

# respawn-pane으로 명령 실행 (새 pane이든 재활용이든 동일)
sleep 0.3
cmux_run respawn-pane --surface "$SURFACE_ID" --command "bash ${LAUNCHER}"

# ─── 에이전트 등록 (workspace 생성 후 정확한 surface_id로) ──
REGISTRY_JSON=$(jq -n \
  --arg id "$AGENT_ID" \
  --arg role "$ROLE" \
  --arg surface_id "$SURFACE_ID" \
  --arg cwd "$PROJECT_CWD" \
  --arg peers "$PEERS" \
  --arg status "running" \
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

log_event "SPAWN" "Agent spawned: ${AGENT_ID} (role=${ROLE}, surface=${SURFACE_ID})"
log_info "Agent spawned: ${AGENT_ID}"

# stdout으로 agent-id 출력
echo "$AGENT_ID"
