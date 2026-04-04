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

# ─── 에이전트 ID 추출 (시그널 이름에서) ──────────────
# 시그널 패턴: {session}:agent:{agent-id}:done
AGENT_ID_FROM_SIGNAL=""
if [[ "$FULL_SIGNAL" =~ :agent:([^:]+): ]]; then
  AGENT_ID_FROM_SIGNAL="${BASH_REMATCH[1]}"
fi

# ─── 시그널 대기 (에이전트가 작업 중이면 자동 연장) ───
log_info "Waiting for signal: ${FULL_SIGNAL} (timeout: ${TIMEOUT}s, auto-extend if agent still working)"

if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
  echo "[$(iso_timestamp)] WAIT_START: ${FULL_SIGNAL} (timeout=${TIMEOUT}s)" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
fi

TOTAL_WAITED=0

while true; do
  if cmux_run wait-for "$FULL_SIGNAL" --timeout "$TIMEOUT"; then
    # 시그널 수신 성공
    if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
      echo "[$(iso_timestamp)] WAIT_RECEIVED: ${FULL_SIGNAL} (after ${TOTAL_WAITED}s + ${TIMEOUT}s)" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
    fi
    log_event "SIGNAL" "Received: ${FULL_SIGNAL}"
    log_info "Signal received: ${FULL_SIGNAL} (total wait: $((TOTAL_WAITED + TIMEOUT))s)"
    exit 0
  fi

  # 타임아웃 — 에이전트가 아직 작업 중인지 확인
  TOTAL_WAITED=$((TOTAL_WAITED + TIMEOUT))

  # outbox에 결과 파일이 있으면 이미 완료된 것 (시그널만 못 받은 경우)
  if [[ -n "$AGENT_ID_FROM_SIGNAL" && -f "${IPC_DIR}/outbox/${AGENT_ID_FROM_SIGNAL}.result.json" ]]; then
    log_info "Result file found for ${AGENT_ID_FROM_SIGNAL} — treating as completed"
    exit 0
  fi

  # 에이전트 registry에서 상태 확인
  AGENT_STILL_RUNNING=false
  if [[ -n "$AGENT_ID_FROM_SIGNAL" && -f "${IPC_DIR}/registry/${AGENT_ID_FROM_SIGNAL}.json" ]]; then
    AGENT_STATUS="$(jq -r '.status' "${IPC_DIR}/registry/${AGENT_ID_FROM_SIGNAL}.json" 2>/dev/null || echo "unknown")"
    AGENT_SURFACE="$(jq -r '.surface_id' "${IPC_DIR}/registry/${AGENT_ID_FROM_SIGNAL}.json" 2>/dev/null || echo "")"

    if [[ "$AGENT_STATUS" == "running" || "$AGENT_STATUS" == "spawning" ]]; then
      # pane이 살아있는지 확인
      if [[ -n "$AGENT_SURFACE" && "$AGENT_SURFACE" != "unknown" ]]; then
        if cmux_run read-screen --surface "$AGENT_SURFACE" --lines 1 &>/dev/null; then
          AGENT_STILL_RUNNING=true
        fi
      else
        # surface 확인 불가 — 일단 작업 중으로 간주
        AGENT_STILL_RUNNING=true
      fi
    fi
  fi

  if [[ "$AGENT_STILL_RUNNING" == true ]]; then
    log_info "Agent still working (waited ${TOTAL_WAITED}s). Extending wait by ${TIMEOUT}s..."
    if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
      echo "[$(iso_timestamp)] WAIT_EXTEND: ${FULL_SIGNAL} (total=${TOTAL_WAITED}s, +${TIMEOUT}s)" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
    fi
    continue
  fi

  # 에이전트가 실행 중이 아님 — 타임아웃 확정
  if [[ -n "$IPC_DIR" && -d "${IPC_DIR}/signals" ]]; then
    echo "[$(iso_timestamp)] WAIT_TIMEOUT: ${FULL_SIGNAL} (total=${TOTAL_WAITED}s)" >> "${IPC_DIR}/signals/signal.log" 2>/dev/null || true
  fi
  log_event "SIGNAL" "Timeout waiting for: ${FULL_SIGNAL} (total: ${TOTAL_WAITED}s)"
  log_error "Signal timeout: ${FULL_SIGNAL} (agent not running, waited ${TOTAL_WAITED}s)"
  exit 1
done
