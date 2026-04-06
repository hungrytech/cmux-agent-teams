#!/usr/bin/env bash
# reset-grid-cursor.sh — 그리드 reuse cursor를 0으로 리셋
#
# 다음 stage에서 기존 pane을 처음부터 재활용하기 위해 호출한다.
# Stage A 완료 후, Stage B 시작 전에 실행.
#
# 사용법:
#   reset-grid-cursor.sh [--session <session-id>]
#
# 종료코드: 0 성공, 1 grid 파일 없음

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

SESSION_ID="$(get_session_id)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"
IPC_DIR="$(get_ipc_dir "$SESSION_ID")"
GRID_FILE="${IPC_DIR}/.agent-grid.json"

if [[ ! -f "$GRID_FILE" ]]; then
  log_error "Grid file not found: ${GRID_FILE}"
  exit 1
fi

jq '.reuse_cursor = 0' "$GRID_FILE" > "${GRID_FILE}.tmp" && mv "${GRID_FILE}.tmp" "$GRID_FILE"

log_info "Grid reuse cursor reset to 0 (total panes: $(jq '.grid | length' "$GRID_FILE"))"
