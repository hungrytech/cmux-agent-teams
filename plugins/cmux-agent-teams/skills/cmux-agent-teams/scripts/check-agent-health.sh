#!/usr/bin/env bash
# check-agent-health.sh — 에이전트 상태 확인
#
# 사용법:
#   check-agent-health.sh --agent <agent-id> [--session <session-id>]
#
# 출력: JSON { agent_id, status, last_output } (stdout)
# status: running | completed | failed | unresponsive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq
require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
AGENT_ID=""
SESSION_ID="$(get_session_id)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT_ID="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

if [[ -z "$AGENT_ID" ]]; then
  log_error "--agent는 필수입니다"
  exit 1
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID")"
REG_FILE="${IPC_DIR}/registry/${AGENT_ID}.json"

if [[ ! -f "$REG_FILE" ]]; then
  jq -n --arg id "$AGENT_ID" --arg status "not_found" \
    '{agent_id: $id, status: $status, last_output: ""}'
  exit 1
fi

SURFACE_ID="$(json_get "$REG_FILE" '.surface_id')"
RESULT_FILE="${IPC_DIR}/outbox/${AGENT_ID}.result.json"

# ─── 상태 판단 ───────────────────────────────────────
STATUS="running"
LAST_OUTPUT=""

# 1. outbox에 결과 파일이 있는지 확인
if [[ -f "$RESULT_FILE" ]]; then
  RESULT_STATUS="$(json_get "$RESULT_FILE" '.payload.status')"
  if [[ "$RESULT_STATUS" == "completed" ]]; then
    STATUS="completed"
  elif [[ "$RESULT_STATUS" == "failed" ]]; then
    STATUS="failed"
  else
    STATUS="completed"
  fi
fi

# 2. cmux read-screen으로 마지막 출력 확인
if [[ "$STATUS" == "running" && -n "$SURFACE_ID" ]]; then
  SCREEN_OUTPUT="$(cmux_run read-screen --surface "$SURFACE_ID" --lines 10 2>/dev/null || echo "")"
  LAST_OUTPUT="$(echo "$SCREEN_OUTPUT" | tail -5 | head -c 500)"

  # Claude 종료 패턴 감지
  if echo "$SCREEN_OUTPUT" | grep -qE '(❯|⏎|\$ $|% $)'; then
    # 프롬프트가 보이면 Claude가 종료된 것
    if [[ ! -f "$RESULT_FILE" ]]; then
      STATUS="completed"  # 결과 파일 없이 종료 — 비정상 완료일 수 있음
    fi
  fi

  # 에러 패턴 감지
  if echo "$SCREEN_OUTPUT" | grep -qiE '(error|fatal|panic|traceback|exception)'; then
    if [[ "$STATUS" == "running" ]]; then
      STATUS="failed"
    fi
  fi
fi

# ─── registry 상태 업데이트 ──────────────────────────
if [[ "$STATUS" != "running" ]]; then
  jq --arg s "$STATUS" '.status = $s' "$REG_FILE" > "${REG_FILE}.tmp"
  mv "${REG_FILE}.tmp" "$REG_FILE"
fi

# ─── 결과 출력 ───────────────────────────────────────
jq -n \
  --arg id "$AGENT_ID" \
  --arg status "$STATUS" \
  --arg surface "$SURFACE_ID" \
  --arg last_output "$LAST_OUTPUT" \
  '{
    agent_id: $id,
    status: $status,
    surface_id: $surface,
    last_output: $last_output
  }'
