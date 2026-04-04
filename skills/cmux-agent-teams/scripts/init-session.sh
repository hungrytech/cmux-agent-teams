#!/usr/bin/env bash
# init-session.sh — IPC 세션 초기화
# 사용법: init-session.sh [--cwd <project-dir>]
# 출력: session-id (stdout)
# 부작용: /tmp/cmux-agent-ipc/{session-id}/ 디렉터리 생성

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq
require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
PROJECT_CWD="${PWD}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cwd) PROJECT_CWD="$2"; shift 2 ;;
    --session) FORCE_SESSION="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# ─── 세션 ID 생성 ────────────────────────────────────
SESSION_ID="${FORCE_SESSION:-$(gen_uuid | cut -d'-' -f1,2)}"
export CMUX_AGENT_SESSION="$SESSION_ID"

IPC_DIR="${IPC_BASE}/${SESSION_ID}"

# ─── 디렉터리 구조 생성 ──────────────────────────────
mkdir -p "${IPC_DIR}/registry"
mkdir -p "${IPC_DIR}/inbox/orchestrator"
mkdir -p "${IPC_DIR}/outbox"
mkdir -p "${IPC_DIR}/prompts"
mkdir -p "${IPC_DIR}/signals"

# ─── session.json 생성 ───────────────────────────────
ORCHESTRATOR_SURFACE="${CMUX_SURFACE_ID:-unknown}"
ORCHESTRATOR_WORKSPACE="${CMUX_WORKSPACE_ID:-unknown}"

SESSION_JSON=$(jq -n \
  --arg id "$SESSION_ID" \
  --arg project_cwd "$PROJECT_CWD" \
  --arg orchestrator_surface "$ORCHESTRATOR_SURFACE" \
  --arg orchestrator_workspace "$ORCHESTRATOR_WORKSPACE" \
  --arg created_at "$(iso_timestamp)" \
  --arg status "active" \
  '{
    id: $id,
    project_cwd: $project_cwd,
    orchestrator: {
      surface_id: $orchestrator_surface,
      workspace_id: $orchestrator_workspace
    },
    created_at: $created_at,
    status: $status,
    agents: [],
    config: {
      max_agents: 6,
      default_timeout_seconds: 300,
      communication_mode: "orchestrated"
    }
  }')

atomic_write "${IPC_DIR}/session.json" "$SESSION_JSON"

log_event "SESSION" "Session initialized: ${SESSION_ID} at ${PROJECT_CWD}"
log_info "Session initialized: ${SESSION_ID}"
log_info "IPC directory: ${IPC_DIR}"

# stdout으로 session ID 출력 (다른 스크립트에서 캡처용)
echo "$SESSION_ID"
