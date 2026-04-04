#!/usr/bin/env bash
# cleanup-session.sh — IPC 세션 정리
#
# 사용법:
#   cleanup-session.sh [--session <session-id>] [--close-panes] [--auto]
#
# --close-panes: 에이전트 pane도 닫기
# --auto: Stop 훅에서 호출 시 사용 (확인 없이 정리)
#
# 종료코드: 0 성공

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

# ─── 인자 파싱 ───────────────────────────────────────
SESSION_ID="$(get_session_id)"
CLOSE_PANES=false
AUTO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)     SESSION_ID="$2"; shift 2 ;;
    --close-panes) CLOSE_PANES=true; shift ;;
    --auto)        AUTO=true; CLOSE_PANES=true; shift ;;
    *) shift ;;
  esac
done

# 세션 ID가 없으면 조용히 종료 (auto 모드에서 정상)
if [[ -z "$SESSION_ID" ]]; then
  [[ "$AUTO" == true ]] && exit 0
  log_error "session_id가 설정되지 않았습니다"
  exit 1
fi

export CMUX_AGENT_SESSION="$SESSION_ID"
IPC_DIR="$(get_ipc_dir "$SESSION_ID" 2>/dev/null || echo "")"

if [[ -z "$IPC_DIR" || ! -d "$IPC_DIR" ]]; then
  [[ "$AUTO" == true ]] && exit 0
  log_info "IPC directory not found, nothing to clean"
  exit 0
fi

# ─── 에이전트 pane 닫기 ──────────────────────────────
if [[ "$CLOSE_PANES" == true ]]; then
  for reg_file in "${IPC_DIR}/registry"/*.json; do
    [[ -f "$reg_file" ]] || continue

    surface_id="$(json_get "$reg_file" '.surface_id' 2>/dev/null || echo "")"
    agent_id="$(json_get "$reg_file" '.id' 2>/dev/null || echo "")"

    if [[ -n "$surface_id" && "$surface_id" != "null" && "$surface_id" != "unknown" ]]; then
      cmux_run close-surface --surface "$surface_id" 2>/dev/null || true
      log_info "Closed pane: ${surface_id} (agent: ${agent_id})"
    fi
  done
fi

# ─── session.json 상태 업데이트 ──────────────────────
if [[ -f "${IPC_DIR}/session.json" ]]; then
  jq '.status = "cleaned_up" | .cleaned_at = now' "${IPC_DIR}/session.json" > "${IPC_DIR}/session.json.tmp" 2>/dev/null
  mv "${IPC_DIR}/session.json.tmp" "${IPC_DIR}/session.json" 2>/dev/null || true
fi

# ─── IPC 디렉터리 삭제 ───────────────────────────────
log_event "CLEANUP" "Session ${SESSION_ID} cleanup started"
rm -rf "$IPC_DIR"

log_info "Session ${SESSION_ID} cleaned up"
