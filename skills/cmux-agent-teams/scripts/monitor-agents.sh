#!/usr/bin/env bash
# monitor-agents.sh — 전체 에이전트 상태 모니터링
#
# 사용법:
#   monitor-agents.sh [--session <session-id>] [--interval <seconds>] [--once]
#
# --interval: 폴링 간격 (기본: 5초)
# --once: 1회만 실행 후 종료
#
# 출력: 에이전트별 상태 JSON (stdout, 반복 출력)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq
require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
SESSION_ID="$(get_session_id)"
INTERVAL=5
ONCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session)  SESSION_ID="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --once)     ONCE=true; shift ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"
IPC_DIR="$(get_ipc_dir "$SESSION_ID")"

# ─── 모니터링 루프 ───────────────────────────────────
check_all_agents() {
  local all_done=true
  local results="[]"

  for reg_file in "${IPC_DIR}/registry"/*.json; do
    [[ -f "$reg_file" ]] || continue

    local agent_id
    agent_id="$(json_get "$reg_file" '.id')"

    local health
    health="$(bash "${SCRIPT_DIR}/check-agent-health.sh" --agent "$agent_id" --session "$SESSION_ID" 2>/dev/null)"

    local status
    status="$(echo "$health" | jq -r '.status')"

    results="$(echo "$results" | jq --argjson h "$health" '. + [$h]')"

    if [[ "$status" == "running" ]]; then
      all_done=false
    fi

    # 완료/실패 시 알림
    if [[ "$status" == "completed" || "$status" == "failed" ]]; then
      local prev_status
      prev_status="$(json_get "$reg_file" '.status')"
      if [[ "$prev_status" == "running" || "$prev_status" == "spawning" ]]; then
        cmux_run notify --title "Agent ${agent_id}" --body "Status: ${status}" 2>/dev/null || true
      fi
    fi
  done

  # 결과 출력
  local summary
  summary="$(echo "$results" | jq '{
    timestamp: now | todate,
    agents: .,
    total: (. | length),
    running: ([.[] | select(.status == "running")] | length),
    completed: ([.[] | select(.status == "completed")] | length),
    failed: ([.[] | select(.status == "failed")] | length)
  }')"

  echo "$summary"

  # 전부 완료 시 all-done 시그널
  if [[ "$all_done" == true && "$(echo "$results" | jq length)" -gt 0 ]]; then
    cmux_run wait-for -S "${SESSION_ID}:all-done" 2>/dev/null || true
    log_event "MONITOR" "All agents completed"
    return 1  # 루프 종료 신호
  fi

  return 0
}

if [[ "$ONCE" == true ]]; then
  check_all_agents
  exit $?
fi

# 반복 모니터링
while true; do
  check_all_agents || break
  sleep "$INTERVAL"
done

log_info "Monitoring finished — all agents completed"
