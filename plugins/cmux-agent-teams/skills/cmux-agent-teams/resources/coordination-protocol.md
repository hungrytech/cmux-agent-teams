# Coordination 프로토콜 — 에이전트 협업 패턴

> Phase 1 (Plan), Phase 3 (Execute)에서 로딩

## 개요

에이전트 간 협업은 4가지 패턴으로 분류된다. 각 패턴은 작업 특성에 따라 선택하며,
혼합(Hybrid) 사용도 가능하다.

## 패턴 1: Pipeline (순차 파이프라인)

### 언제 사용하는가
- 이전 에이전트의 결과물이 다음 에이전트의 입력이 되는 경우
- 레이어별 분업 (모델 → 서비스 → 컨트롤러)
- 단계적 의존성이 명확한 작업

### 흐름

```
Agent-A ──done-signal──→ Orchestrator ──task+context──→ Agent-B ──done-signal──→ ...
```

### 구현

```bash
# 1. 첫 번째 에이전트 실행
AGENT_A=$(spawn-agent.sh --role "backend-model" --task "Entity 설계")

# 2. 완료 대기
wait-signal.sh --name "agent:${AGENT_A}:done" --timeout 300

# 3. 결과 읽기
RESULT_A=$(cat /tmp/cmux-agent-ipc/${SESSION}/outbox/${AGENT_A}.result.json)

# 4. 다음 에이전트에 결과 전달
AGENT_B=$(spawn-agent.sh --role "backend-service" \
  --task "Service 구현 (이전 에이전트 결과 참조: ${AGENT_A})")

# Agent-B의 inbox에 의존성 결과 포함하여 추가 메시지 전송
send-message.sh --to "$AGENT_B" --type "task" \
  --payload "{\"task_description\":\"Service 구현\",\"context\":{\"dependency_results\":[${RESULT_A}]}}"
```

### 실패 처리
- 중간 에이전트 실패 시: 파이프라인 중단, 사용자에게 보고
- 부분 결과 수집 가능

### 예시 시나리오

**백엔드 레이어 분업:**
```
Stage 1: Entity/Model 정의
  ↓ artifacts: [User.kt, Order.kt]
Stage 2: Repository + Service 구현
  ↓ artifacts: [UserRepository.kt, OrderService.kt]
Stage 3: Controller + DTO 매핑
  ↓ artifacts: [UserController.kt, UserDto.kt]
```

**풀스택 API:**
```
Stage 1: OpenAPI Spec 설계
  ↓ artifacts: [openapi.yaml]
Stage 2: Backend 구현
  ↓ artifacts: [controllers/, services/]
Stage 3: Frontend API 연동
  ↓ artifacts: [hooks/useApi.ts, types/api.ts]
```

---

## 패턴 2: Fanout (병렬 분산)

### 언제 사용하는가
- 에이전트들이 서로 독립적인 작업을 수행하는 경우
- 동시에 여러 모듈/도메인을 개발
- 분석/리뷰 작업의 병렬화

### 흐름

```
Orchestrator ──spawn──→ Agent-A ─┐
             ──spawn──→ Agent-B ─┤──all-done──→ Collect
             ──spawn──→ Agent-C ─┘
```

### 구현

```bash
# 1. 모든 에이전트 동시 생성
AGENT_A=$(spawn-agent.sh --role "auth-module" --task "인증 모듈 구현" --direction right)
AGENT_B=$(spawn-agent.sh --role "order-module" --task "주문 모듈 구현" --direction down)
AGENT_C=$(spawn-agent.sh --role "notification-module" --task "알림 모듈 구현" --direction down)

# 2. 모든 에이전트 완료 대기
wait-signal.sh --name "agent:${AGENT_A}:done" --timeout 300 &
wait-signal.sh --name "agent:${AGENT_B}:done" --timeout 300 &
wait-signal.sh --name "agent:${AGENT_C}:done" --timeout 300 &
wait  # 모든 백그라운드 프로세스 완료 대기

# 3. 또는 monitor-agents.sh 사용
monitor-agents.sh --once  # 전부 완료될 때까지 대기
```

### 실패 처리
- 개별 에이전트 실패는 다른 에이전트에 영향 없음
- 부분 결과 수집 후 보고

### 예시 시나리오

**도메인별 병렬 개발:**
```
┌─→ Agent-A: 사용자 인증 (User + Auth)
├─→ Agent-B: 주문 관리 (Order + Payment)
└─→ Agent-C: 알림 (Notification + Email)
→ 전부 완료 후 통합
```

**코드 리뷰 + 성능 분석:**
```
┌─→ Agent-A: 코드 리뷰 (SOLID, 코드 스멜)
└─→ Agent-B: 성능 분석 (쿼리 최적화, 캐싱)
→ 결과 병합 → 통합 리포트
```

---

## 패턴 3: Feedback (반복 피드백 루프)

### 언제 사용하는가
- 설계 → 리뷰 → 수정 반복이 필요한 경우
- 품질 기준 충족까지 반복
- 최대 반복 횟수 제한 (기본 2회)

### 흐름

```
Agent-A (설계) → Agent-B (리뷰) → issues? → Agent-A (수정) → Agent-B (재리뷰)
                                    ↓ no issues
                                  Complete
```

### 구현

```bash
MAX_ITERATIONS=2
ITERATION=0

AGENT_A=$(spawn-agent.sh --role "api-designer" --task "API 설계" --direction right)

while [[ $ITERATION -lt $MAX_ITERATIONS ]]; do
  wait-signal.sh --name "agent:${AGENT_A}:done" --timeout 300

  # 리뷰 에이전트 실행
  AGENT_B=$(spawn-agent.sh --role "code-reviewer" \
    --task "Agent-A 결과 리뷰: ${IPC_DIR}/outbox/${AGENT_A}.result.json" \
    --direction down)
  wait-signal.sh --name "agent:${AGENT_B}:done" --timeout 300

  # 리뷰 결과 확인
  REVIEW_STATUS=$(json_get "${IPC_DIR}/outbox/${AGENT_B}.result.json" '.payload.status')

  if [[ "$REVIEW_STATUS" == "completed" ]]; then
    # 이슈 없음 → 종료
    break
  fi

  # 이슈 있음 → Agent-A에 피드백 전달 후 재실행
  ITERATION=$((ITERATION + 1))
  send-message.sh --to "$AGENT_A" --type "peer-request" \
    --payload "{\"task_description\":\"리뷰 피드백 반영\",\"artifacts\":[\"${IPC_DIR}/outbox/${AGENT_B}.result.json\"]}" \
    --signal
done
```

### 수렴 기준
- 리뷰 에이전트가 "completed" (이슈 없음) 반환
- 또는 최대 반복 횟수 도달

---

## 패턴 4: Hybrid (혼합)

### 언제 사용하는가
- 분석(Fanout) → 구현(Pipeline) 등 여러 패턴의 조합
- 복잡한 프로젝트에서 가장 빈번하게 사용

### 흐름

```
Fanout Stage:
  ├── Agent-A: 코드 분석
  └── Agent-B: DB 스키마 분석
       ↓ both:done
Pipeline Stage:
  Agent-C: 마이그레이션 스크립트
       ↓ done
  Agent-D: 코드 리팩토링
       ↓ done
  Agent-E: 테스트 작성
```

### 구현

스테이지 단위로 패턴을 적용:

```bash
# Stage 1: Fanout (병렬 분석)
AGENT_A=$(spawn-agent.sh --role "code-analyzer" --task "기존 코드 분석")
AGENT_B=$(spawn-agent.sh --role "db-analyzer" --task "DB 스키마 분석")
wait-signal.sh --name "agent:${AGENT_A}:done"
wait-signal.sh --name "agent:${AGENT_B}:done"

# Stage 2: Pipeline (순차 구현)
AGENT_C=$(spawn-agent.sh --role "migration" \
  --task "마이그레이션 스크립트 (분석 결과: ${AGENT_A}, ${AGENT_B})")
wait-signal.sh --name "agent:${AGENT_C}:done"

AGENT_D=$(spawn-agent.sh --role "refactor" --task "코드 리팩토링")
wait-signal.sh --name "agent:${AGENT_D}:done"
```

---

## Peer-to-Peer 직접 통신

Orchestrated 패턴의 대안으로, 에이전트가 직접 소통.

### 언제 사용하는가
- 동일 도메인 에이전트 간 빠른 협업 필요 시
- 오케스트레이터 병목을 피하고 싶을 때
- 에이전트가 자율적으로 작업 순서를 조율할 때

### 흐름

```
Agent-A ──peer-request + signal──→ Agent-B
Agent-B ──peer-response + signal──→ Agent-A (필요 시)
```

### 에이전트 발견

```bash
# registry에서 특정 역할의 에이전트 찾기
ls /tmp/cmux-agent-ipc/${SESSION}/registry/
cat /tmp/cmux-agent-ipc/${SESSION}/registry/*.json | jq 'select(.role == "backend-service")'
```

### 예시: 백엔드 레이어 간 P2P

```
Agent-A (Model):
  1. Entity 정의 완료
  2. outbox에 결과 쓰기 (artifacts: [User.kt, Order.kt])
  3. Agent-B inbox에 peer-request 쓰기
  4. cmux wait-for -S "{session}:agent:agent-b:peer-msg"

Agent-B (Service):
  1. cmux wait-for "{session}:agent:agent-b:peer-msg" (대기)
  2. inbox에서 peer-request 읽기
  3. Agent-A outbox의 artifacts 참��
  4. Service 레이어 구현
  5. outbox에 결과 쓰기
  6. Agent-C inbox에 peer-request 쓰기 (다음 레이어)
  7. cmux wait-for -S "{session}:agent:agent-c:peer-msg"
```

---

## 패턴 선택 가이드

| 작업 특성 | 추천 패턴 | 이유 |
|-----------|-----------|------|
| 레이어별 분업 (모델→서비스→컨트롤러) | Pipeline 또는 P2P | 순차 의존성 |
| 독립 도메인 병렬 개발 | Fanout | 상호 무관 |
| API 구현 + API 연동 | Pipeline | 명확한 의존성 |
| 설계 + 리뷰 반복 | Feedback | 품질 수렴 |
| 분석 후 구현 | Hybrid (Fanout→Pipeline) | 단계별 전환 |
| 같은 레이어 내 협업 | P2P + Fanout | 빠른 직접 통신 |
| CRUD + 테스트 병렬 | P2P | 점진적 파이프라인 |
