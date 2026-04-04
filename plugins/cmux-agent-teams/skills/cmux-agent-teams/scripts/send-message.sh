#!/usr/bin/env bash
# send-message.sh — 에이전트 inbox에 메시지 전송
#
# 사���법:
#   send-message.sh --to <agent-id|broadcast> --type <type> --payload <json-string> \
#     [--from <sender-id>] [--session <session-id>] [--signal]
#
# --type: task | result | signal | error | peer-request | peer-response
# --to: 특정 agent-id 또는 "broadcast" (전체 에이전트)
# --signal: 메시지 전송 후 cmux wait-for -S 시그널도 전송
#
# 출력: message-id (stdout)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ─── 인자 파싱 ───────────────────────────────────────
TO=""
MSG_TYPE=""
PAYLOAD=""
FROM="orchestrator"
SESSION_ID="$(get_session_id)"
SEND_SIGNAL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)      TO="$2"; shift 2 ;;
    --type)    MSG_TYPE="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    --from)    FROM="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    --signal)  SEND_SIGNAL=true; shift ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

if [[ -z "$TO" || -z "$MSG_TYPE" || -z "$PAYLOAD" ]]; then
  log_error "--to, --type, --payload는 모두 필수입니다"
  echo "사용법: send-message.sh --to <agent-id|broadcast> --type <type> --payload <json-string>" >&2
  exit 1
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID")"

# ─── 메시지 생성 ─────────────────────────────────────
MSG_ID="$(gen_uuid)"
TIMESTAMP="$(iso_timestamp)"

# payload가 유효한 JSON인지 확인, 아니면 문자열로 감싸기
if echo "$PAYLOAD" | jq . &>/dev/null; then
  PAYLOAD_JSON="$PAYLOAD"
else
  PAYLOAD_JSON=$(jq -n --arg p "$PAYLOAD" '{task_description: $p}')
fi

MSG_JSON=$(jq -n \
  --arg id "$MSG_ID" \
  --arg type "$MSG_TYPE" \
  --arg from "$FROM" \
  --arg to "$TO" \
  --arg timestamp "$TIMESTAMP" \
  --argjson payload "$PAYLOAD_JSON" \
  '{
    id: $id,
    type: $type,
    from: $from,
    to: $to,
    timestamp: $timestamp,
    payload: $payload
  }')

# ─── 메시지 전송 ─────────────────────────────────────
send_to_agent() {
  local target_id="$1"
  local inbox_dir="${IPC_DIR}/inbox/${target_id}"

  if [[ ! -d "$inbox_dir" ]]; then
    mkdir -p "$inbox_dir"
  fi

  atomic_write "${inbox_dir}/${MSG_ID}.json" "$MSG_JSON"
  log_event "MSG_SEND" "Message ${MSG_ID} (${MSG_TYPE}) from ${FROM} to ${target_id}"
}

if [[ "$TO" == "broadcast" ]]; then
  # 모든 에이전트에게 전송
  for reg_file in "${IPC_DIR}/registry"/*.json; do
    [[ -f "$reg_file" ]] || continue
    local_agent_id="$(json_get "$reg_file" '.id')"
    send_to_agent "$local_agent_id"
  done
  log_info "Broadcast message sent: ${MSG_ID}"
else
  send_to_agent "$TO"
  log_info "Message sent to ${TO}: ${MSG_ID}"
fi

# ─── 시그널 전송 (선택) ──────────────────────────────
if [[ "$SEND_SIGNAL" == true ]]; then
  require_cmux
  if [[ "$TO" == "broadcast" ]]; then
    cmux_run wait-for -S "${SESSION_ID}:broadcast:${MSG_TYPE}"
  else
    cmux_run wait-for -S "${SESSION_ID}:agent:${TO}:${MSG_TYPE}"
  fi
  log_info "Signal sent: ${SESSION_ID}:agent:${TO}:${MSG_TYPE}"
fi

echo "$MSG_ID"
