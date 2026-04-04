# Orchestration Plan

**Session**: {{SESSION_ID}}
**Pattern**: {{PATTERN}}
**Project**: {{PROJECT_CWD}}
**Created**: {{TIMESTAMP}}
**Total Agents**: {{AGENT_COUNT}}

## 작업 개요

{{TASK_OVERVIEW}}

## 에이전트 구성

| # | Agent ID | Role | Direction | Depends On | Task |
|---|----------|------|-----------|------------|------|
{{AGENT_TABLE}}

## 실행 전략

### Pattern: {{PATTERN}}

{{PATTERN_DESCRIPTION}}

## 스테이지

{{STAGES}}

## 시그널 흐름

```
{{SIGNAL_FLOW_DIAGRAM}}
```

## 타임아웃

- 개별 에이전트: {{AGENT_TIMEOUT}}초
- 전체 세션: {{SESSION_TIMEOUT}}초

## 실패 처리

- 에이전트 실패 시: 해당 에이전트 결과를 partial로 기록, 의존 에이전트에게 알림
- 타임아웃 시: 모니터가 감지하여 cleanup 시작
- 전체 실패 시: 부분 결과 수집 후 사용자에게 보고
