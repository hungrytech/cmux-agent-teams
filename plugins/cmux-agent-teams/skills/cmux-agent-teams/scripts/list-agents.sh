#!/usr/bin/env bash
# list-agents.sh — 등록된 에이전트 목록 조회
#
# 사용법:
#   list-agents.sh [--session <session-id>] [--role <filter-role>] [--status <filter-status>]
#
# 출력: JSON 배열 (stdout)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_jq

# ─── 인자 파싱 ───────────────────────────────────────
SESSION_ID="$(get_session_id)"
FILTER_ROLE=""
FILTER_STATUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ID="$2"; shift 2 ;;
    --role)    FILTER_ROLE="$2"; shift 2 ;;
    --status)  FILTER_STATUS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"
IPC_DIR="$(get_ipc_dir "$SESSION_ID")"

if [[ ! -d "${IPC_DIR}/registry" ]]; then
  echo "[]"
  exit 0
fi

# ─── 에이전트 수집 ───────────────────────────────────
AGENTS="[]"

for reg_file in "${IPC_DIR}/registry"/*.json; do
  [[ -f "$reg_file" ]] || continue

  agent_json="$(cat "$reg_file")"

  # role 필터
  if [[ -n "$FILTER_ROLE" ]]; then
    agent_role="$(echo "$agent_json" | jq -r '.role')"
    [[ "$agent_role" != *"$FILTER_ROLE"* ]] && continue
  fi

  # status 필터
  if [[ -n "$FILTER_STATUS" ]]; then
    agent_status="$(echo "$agent_json" | jq -r '.status')"
    [[ "$agent_status" != "$FILTER_STATUS" ]] && continue
  fi

  # outbox 결과 존재 여부 추가
  agent_id="$(echo "$agent_json" | jq -r '.id')"
  has_result=false
  if [[ -f "${IPC_DIR}/outbox/${agent_id}.result.json" ]]; then
    has_result=true
  fi

  # inbox 메시지 수 추가
  inbox_count=0
  if [[ -d "${IPC_DIR}/inbox/${agent_id}" ]]; then
    inbox_count="$(find "${IPC_DIR}/inbox/${agent_id}" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
  fi

  agent_json="$(echo "$agent_json" | jq \
    --argjson has_result "$has_result" \
    --argjson inbox_count "$inbox_count" \
    '. + {has_result: $has_result, inbox_pending: $inbox_count}')"

  AGENTS="$(echo "$AGENTS" | jq --argjson agent "$agent_json" '. + [$agent]')"
done

echo "$AGENTS" | jq '.'
