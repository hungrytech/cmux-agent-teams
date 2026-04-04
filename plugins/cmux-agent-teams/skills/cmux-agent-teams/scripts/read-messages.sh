#!/usr/bin/env bash
# read-messages.sh — 에이전트 inbox에서 메시지 읽기
#
# 사용법:
#   read-messages.sh --agent <agent-id> [--consume] [--type <filter-type>] \
#     [--session <session-id>] [--latest]
#
# --consume: 읽은 메시지를 .consumed/로 이동
# --type: 특정 타입 메시지만 필터링
# --latest: 가장 최근 메시지 1개만 출력
#
# 출력: JSON 배열 (stdout)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ─── 인자 파싱 ───────────────────────────────────────
AGENT_ID=""
CONSUME=false
FILTER_TYPE=""
SESSION_ID="$(get_session_id)"
LATEST_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT_ID="$2"; shift 2 ;;
    --consume) CONSUME=true; shift ;;
    --type)    FILTER_TYPE="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    --latest)  LATEST_ONLY=true; shift ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

if [[ -z "$AGENT_ID" ]]; then
  log_error "--agent는 필수입니다"
  exit 1
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID")"
INBOX_DIR="${IPC_DIR}/inbox/${AGENT_ID}"

if [[ ! -d "$INBOX_DIR" ]]; then
  echo "[]"
  exit 0
fi

# ─── 메시지 수집 ─────────────────────────────────────
MESSAGES="[]"
CONSUMED_DIR="${INBOX_DIR}/.consumed"

for msg_file in "${INBOX_DIR}"/*.json; do
  [[ -f "$msg_file" ]] || continue

  # 타입 필터링
  if [[ -n "$FILTER_TYPE" ]]; then
    msg_type="$(json_get "$msg_file" '.type')"
    [[ "$msg_type" != "$FILTER_TYPE" ]] && continue
  fi

  msg_content="$(cat "$msg_file")"
  MESSAGES="$(echo "$MESSAGES" | jq --argjson msg "$msg_content" '. + [$msg]')"

  # consume 모드: 읽은 메시지 이동
  if [[ "$CONSUME" == true ]]; then
    mkdir -p "$CONSUMED_DIR"
    mv "$msg_file" "$CONSUMED_DIR/"
  fi
done

# 타임스탬프 기준 정렬
MESSAGES="$(echo "$MESSAGES" | jq 'sort_by(.timestamp)')"

# latest only
if [[ "$LATEST_ONLY" == true ]]; then
  MESSAGES="$(echo "$MESSAGES" | jq '.[length-1:length]')"
fi

echo "$MESSAGES"
