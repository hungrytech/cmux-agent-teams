#!/usr/bin/env bash
# wait-signal.sh — cmux wait-for 시그널 대기 (블로킹)
#
# 사용법:
#   wait-signal.sh --name <signal-name> [--timeout <seconds>] [--session <session-id>]
#
# 종료코드: 0 시그널 수신, 1 타임아웃/에러

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

require_cmux

# ─── 인자 파싱 ───────────────────────────────────────
SIGNAL_NAME=""
TIMEOUT=300
SESSION_ID="$(get_session_id)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)    SIGNAL_NAME="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --session) SESSION_ID="$2"; shift 2 ;;
    *) shift ;;
  esac
done

export CMUX_AGENT_SESSION="$SESSION_ID"

if [[ -z "$SIGNAL_NAME" ]]; then
  log_error "--name은 필수입니다"
  exit 1
fi

# 세션 prefix 자동 추가
if [[ "$SIGNAL_NAME" != "${SESSION_ID}:"* && -n "$SESSION_ID" ]]; then
  FULL_SIGNAL="${SESSION_ID}:${SIGNAL_NAME}"
else
  FULL_SIGNAL="$SIGNAL_NAME"
fi

IPC_DIR="$(get_ipc_dir "$SESSION_ID" 2>/dev/null || echo "")"

# ─── 시그널 대기 ─────────────────────────────────────
log_info "Waiting for signal: ${FULL_SIGNAL} (timeout: ${TIMEOUT}s)"

if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
  echo "[$(iso_timestamp)] WAIT_START: ${FULL_SIGNAL} (timeout=${TIMEOUT}s)" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
fi

if cmux_run wait-for "$FULL_SIGNAL" --timeout "$TIMEOUT"; then
  if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
    echo "[$(iso_timestamp)] WAIT_RECEIVED: ${FULL_SIGNAL}" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
  fi
  log_event "SIGNAL" "Received: ${FULL_SIGNAL}"
  log_info "Signal received: ${FULL_SIGNAL}"
  exit 0
else
  if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
    echo "[$(iso_timestamp)] WAIT_TIMEOUT: ${FULL_SIGNAL}" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
  fi
  log_event "SIGNAL" "Timeout waiting for: ${FULL_SIGNAL}"
  log_error "Signal timeout: ${FULL_SIGNAL}"
  exit 1
fi
