#!/usr/bin/env bash
# _common.sh — cmux-agent-teams 공통 함수
# 모든 스크립트에서 source 하여 사용

set -euo pipefail

# ─── ���수 ────────────────────────────────────────────
IPC_BASE="/tmp/cmux-agent-ipc"
CMUX_BIN="${CMUX_BIN:-cmux}"

# ─���─ 세션 ID ─────────────────────────────────────────
get_session_id() {
  echo "${CMUX_AGENT_SESSION:-}"
}

get_ipc_dir() {
  local session_id="${1:-$(get_session_id)}"
  if [[ -z "$session_id" ]]; then
    echo "ERROR: session_id가 설���되지 않았습니다. init-session.sh를 먼저 실행하세요." >&2
    return 1
  fi
  echo "${IPC_BASE}/${session_id}"
}

# ─── UUID 생성 ──────��────────────────────────────────
gen_uuid() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    printf '%s-%04x' "$(date +%s%N 2>/dev/null || date +%s)" $((RANDOM % 65536))
  fi
}

# ─── 타임스탬프 ──────────────────────────────────────
iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ���── JSON 헬퍼 ───────────────────────────────────��───
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq가 설치되어 있지 않습니다. brew install jq 또는 apt install jq로 설치하세요." >&2
    return 1
  fi
}

json_get() {
  local file="$1" expr="$2"
  jq -r "$expr" "$file" 2>/dev/null
}

json_obj() {
  local args=()
  while [[ $# -ge 2 ]]; do
    args+=("--arg" "$1" "$2")
    shift 2
  done
  jq -n "${args[@]}" '$ARGS.named'
}

# ─── cmux 유틸리티 ───────────────────────────────────
require_cmux() {
  if ! command -v "$CMUX_BIN" &>/dev/null; then
    echo "ERROR: cmux가 설치되어 있지 않습니다." >&2
    return 1
  fi
}

cmux_run() {
  local session_id ipc_dir
  session_id="$(get_session_id)"
  ipc_dir="$(get_ipc_dir "$session_id" 2>/dev/null || echo "")"
  if [[ -n "$ipc_dir" && -d "$ipc_dir" ]]; then
    echo "[$(iso_timestamp)] cmux $*" >> "${ipc_dir}/cmux-debug.log" 2>/dev/null || true
  fi
  "$CMUX_BIN" "$@"
}

# ─── 에이전트 ID 생성 ────────────────────────────────
gen_agent_id() {
  local role="${1:-agent}"
  local clean_role
  clean_role="$(echo "$role" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g' | head -c 20)"
  local short_uuid
  short_uuid="$(gen_uuid | cut -d'-' -f1)"
  echo "${clean_role}-${short_uuid}"
}

# ─── 원자적 파일 쓰기 ────────────────────────────────
atomic_write() {
  local target="$1"
  local content="$2"
  local tmp="${target}.tmp.$$"
  echo "$content" > "$tmp"
  mv "$tmp" "$target"
}

# ─── 로깅 ────────────────────────────────────────────
log_info() {
  echo "[INFO] $(iso_timestamp) $*" >&2
}

log_error() {
  echo "[ERROR] $(iso_timestamp) $*" >&2
}

log_event() {
  local session_id event_type message
  session_id="$(get_session_id)"
  event_type="$1"
  shift
  message="$*"
  local ipc_dir
  ipc_dir="$(get_ipc_dir "$session_id" 2>/dev/null || echo "")"
  if [[ -n "$ipc_dir" && -d "$ipc_dir" ]]; then
    echo "[$(iso_timestamp)] [$event_type] $message" >> "${ipc_dir}/events.log" 2>/dev/null || true
  fi
}
