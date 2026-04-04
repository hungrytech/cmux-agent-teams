#!/usr/bin/env bash
# signal-agent.sh — cmux wait-for 시그널 전송
#
# 사용법:
#   signal-agent.sh --name <signal-name> [--session <session-id>]
#
# 시그널 네이밍 컨벤션:
#   {session}:agent:{agent-id}:ready  — 에이전트 준비 완료
#   {session}:agent:{agent-id}:done   — 작업 완료
#   {session}:agent:{agent-id}:error  — 에러 발생
#   {session}:stage:{name}:done       — 파이프라인 스테이지 완료
#   {session}:all-done                — 전체 완료
#   {session}:agent:{id}:peer-msg     — P2P 메시지 도착 알림
#
# 종료코드: 0 성공, 1 실패

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
SIGNAL_NAME=""
SESSION_ID="$(get_session_id)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    SIGNAL_NAME="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

if [[ -z "$SIGNAL_NAME" ]]; then
  log_error "--name은 필수입니다"
  exit 1
fi

# 세션 prefix가 없으면 자동 추가
if [[ "$SIGNAL_NAME" != "${SESSION_ID}:"* && -n "$SESSION_ID" ]]; then
  FULL_SIGNAL="${SESSION_ID}:${SIGNAL_NAME}"
else
  FULL_SIGNAL="$SIGNAL_NAME"
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID" 2>/dev/null || echo "")"

# ─── 시그널 전송 ─────────────────────────────────────
cmux_run wait-for -S "$FULL_SIGNAL"

# 시그널 로그 기록
if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
  echo "[$(iso_timestamp)] SIGNAL_SENT: ${FULL_SIGNAL}" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
fi

log_event "SIGNAL" "Sent: ${FULL_SIGNAL}"
log_info "Signal sent: ${FULL_SIGNAL}"
