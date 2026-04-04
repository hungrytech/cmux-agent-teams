# cmux-agent-teams

**cmux 기반 멀티 에이전트 병렬 실행 플러그인** — 여러 Claude Code 인스턴스를 cmux 터미널 pane에서 동시에 실행하고, 에이전트 간 파일 기반 IPC와 시그널 동기화로 실시간 협업을 구현합니다.

백엔드끼리, 프론트끼리, 풀스택 파이프라인, 레거시 프로젝트 마이그레이션 — 어떤 조합이든 지원합니다.

---

## 목차

- [왜 사용해야 하는가](#왜-사용해야-하는가)
- [요구사항](#요구사항)
- [설치](#설치)
- [빠른 시작](#빠른-시작)
- [아키텍처](#아키텍처)
- [사용 시나리오](#사용-시나리오)
- [실행 패턴](#실행-패턴)
- [IPC 프로토콜](#ipc-프로토콜)
- [스크립트 레퍼런스](#스크립트-레퍼런스)
- [메시지 포맷 레퍼런스](#메시지-포맷-레퍼런스)
- [시그널 네이밍 컨벤션](#시그널-네이밍-컨벤션)
- [Peer-to-Peer 통신](#peer-to-peer-통신)
- [서브에이전트 (teammateMode)](#서브에이전트-teammatemode)
- [외부 스킬 연동](#외부-스킬-연동)
- [제한사항 및 트러블슈팅](#제한사항-및-트러블슈팅)
- [라이선스](#라이선스)

---

## 왜 사용해야 하는가

### 문제: Claude Code 단일 세션의 한계

Claude Code는 강력하지만, 한 세션에서 한 번에 하나의 작업만 수행할 수 있습니다. 복잡한 프로젝트에서 이것은 심각한 병목이 됩니다.

**예시: 일반적인 API 개발 워크플로우**

```
순차 실행 (기존 방식):
  Entity 설계     [====]                              30분
  Service 구현          [========]                     60분
  Controller 구현                 [======]             45분
  프론트 연동                            [========]    60분
  테스트 작성                                    [====] 30분
  ─────────────────────────────────────────────────────
  총 소요시간: 225분 (3시간 45분)
```

### 해결: 멀티 에이전트 병렬 실행

cmux-agent-teams를 사용하면 독립적인 작업을 병렬로 실행하고, 의존성이 있는 작업은 시그널 기반 파이프라인으로 연결합니다.

```
병렬 실행 (cmux-agent-teams):
  Entity 설계     [====]
  Service 구현          [========]
  Controller 구현                 [======]
  프론트 연동                            [========]
  테스트 작성          [====][====][====][====]  ← API 하나씩 완료될 때마다 P2P로 시작
  ─────────────────────────────────────────────
  총 소요시간: ~150분 (2시간 30분) — 33% 단축
```

독립 도메인 병렬 개발이라면 효과는 더 큽니다:

```
병렬 실행 (독립 모듈):
  인증 모듈    [===========]                60분
  주문 모듈    [===============]            75분  ← 가장 긴 작업이 전체 시간
  알림 모듈    [========]                   45분
  ─────────────────────────────────
  총 소요시간: 75분 (순차 실행 시 180분 → 58% 단축)
```

### Agent Tool과의 차이점

Claude Code의 내장 Agent Tool도 서브에이전트를 실행할 수 있지만 근본적인 한계가 있습니다:

| 특성 | Agent Tool | cmux-agent-teams |
|------|-----------|------------------|
| 실행 방식 | 단일 프로세스 내 서브태스크 | 독립 터미널에서 별도 Claude 인스턴스 |
| 에이전트 간 통신 | 불가 (결과만 반환) | 실시간 P2P 메시지 + 시그널 |
| 중간 결과 공유 | 불가 | outbox/inbox로 즉시 공유 |
| 진행 상황 확인 | 완료까지 대기 | `read-screen`으로 실시간 모니터링 |
| 에이전트 자율성 | 제한적 | 독립 실행, 자체 도구 사용 가능 |
| 플러그인 사용 | 불가 | 각 에이전트가 별도 플러그인 로딩 가능 |

### 어떤 프로젝트에서든 사용 가능

cmux-agent-teams는 특정 프레임워크나 프로젝트 구조를 가정하지 않습니다.

- Spring Boot, React, Next.js, Go, Python, Ruby — 어떤 스택이든 OK
- 레거시 프로젝트에도 바로 적용
- CLAUDE.md, package.json, build.gradle 등을 자동 감지하여 에이전트에 컨텍스트 주입
- Expert skill 플러그인이 없어도 커스텀 역할로 실행 가능

---

## 요구사항

| 요구사항 | 버전 | 확인 방법 |
|----------|------|-----------|
| **cmux** | 최신 | `cmux version` |
| **Claude Code** | 최신 | `claude --version` |
| **bash** | 4.0+ | `bash --version` |
| **jq** | 1.6+ | `jq --version` |

cmux는 https://cmux.dev 에서 설치할 수 있습니다.

---

## 설치

### 방법 1: GitHub에서 원격 설치 (권장)

Claude Code의 플러그인 마켓플레이스 시스템을 통해 GitHub에서 직접 설치할 수 있습니다.
별도로 clone하거나 파일을 관리할 필요가 없으며, 업데이트도 자동으로 반영됩니다.

```bash
# 1. 마켓플레이스로 GitHub 레포 등록
/plugin marketplace add hungrytech/cmux-agent-teams

# 2. 플러그인 설치
/plugin install cmux-agent-teams@cmux-agent-teams
```

또는 CLI에서 직접:

```bash
claude plugin marketplace add hungrytech/cmux-agent-teams
claude plugin install cmux-agent-teams@cmux-agent-teams
```

#### 설치 범위 (Scope) 지정

```bash
# 나만 사용 (기본)
/plugin install cmux-agent-teams@cmux-agent-teams --scope user

# 프로젝트 팀원 전체가 사용 (프로젝트 .claude/settings.json에 기록)
/plugin install cmux-agent-teams@cmux-agent-teams --scope project
```

`--scope project`로 설치하면 `.claude/settings.json`에 플러그인 정보가 기록되어,
팀원이 해당 프로젝트에서 Claude Code를 시작할 때 자동으로 플러그인이 활성화됩니다.

#### 특정 버전 고정

```bash
# 특정 태그/브랜치 고정
/plugin marketplace add https://github.com/hungrytech/cmux-agent-teams.git#v1.0.0
```

#### settings.json으로 사전 설정

프로젝트의 `.claude/settings.json`에 직접 추가하여 팀 전체가 자동으로 사용하도록 설정할 수 있습니다:

```json
{
  "extraKnownMarketplaces": {
    "cmux-agent-teams": {
      "source": {
        "source": "github",
        "repo": "hungrytech/cmux-agent-teams"
      }
    }
  },
  "enabledPlugins": {
    "cmux-agent-teams@cmux-agent-teams": true
  }
}
```

### 방법 2: Git Clone + 로컬 설치

직접 clone하여 로컬에서 사용하거나, 코드를 수정하여 커스터마이징할 때 적합합니다.

```bash
# 1. clone
git clone https://github.com/hungrytech/cmux-agent-teams.git ~/cmux-agent-teams

# 2. 로컬 마켓플레이스로 등록
/plugin marketplace add ~/cmux-agent-teams
/plugin install cmux-agent-teams@cmux-agent-teams
```

### 방법 3: --plugin-dir로 직접 참조

설치 없이 일회성으로 사용하거나, 개발 중 테스트할 때 적합합니다.

```bash
# 플러그인 디렉터리를 직접 지정 (plugins/ 하위의 실제 플러그인 경로)
claude --plugin-dir ~/cmux-agent-teams/plugins/cmux-agent-teams
```

### 설치 확인

```bash
# cmux 터미널에서 Claude Code 시작 후
> /cmux-agent-teams --help

# 설치된 플러그인 목록 확인
/plugin list
```

---

## 빠른 시작

### 예제 1: 백엔드 API 개발 (Pipeline)

```bash
# cmux 터미널에서 프로젝트 디렉터리로 이동
cd /path/to/your-spring-project

# Claude Code 시작
claude --plugin-dir ~/cmux-agent-teams

# 스킬 호출
> /cmux-agent-teams pipeline "User 도메인 API 개발: Entity 설계 → Service 구현 → Controller 작성"
```

Claude가 자동으로:
1. 작업을 3개 에이전트로 분해
2. cmux pane 3개 생성
3. Entity 에이전트 실행 → 완료 시그널 → Service 에이전트 실행 → ... 순차 진행
4. 모든 에이전트 완료 후 통합 보고서 생성

### 예제 2: 독립 모듈 병렬 개발 (Fanout)

```bash
> /cmux-agent-teams fanout "3개 독립 모듈 병렬 개발: 인증(Auth), 주문(Order), 알림(Notification)"
```

### 예제 3: 수동 스크립트 실행

```bash
# 1. 세션 초기화
SESSION=$(bash ~/cmux-agent-teams/plugins/cmux-agent-teams/skills/cmux-agent-teams/scripts/init-session.sh)
export CMUX_AGENT_SESSION=$SESSION

# 2. 에이전트 생성
SCRIPTS=~/cmux-agent-teams/plugins/cmux-agent-teams/skills/cmux-agent-teams/scripts

AGENT_A=$(bash $SCRIPTS/spawn-agent.sh \
  --role "backend-model" \
  --task "User, Order, Payment Entity 클래스 설계" \
  --direction right)

AGENT_B=$(bash $SCRIPTS/spawn-agent.sh \
  --role "backend-service" \
  --task "Service 레이어 구현" \
  --direction down \
  --peers "$AGENT_A")

# 3. Agent-A 완료 대기
bash $SCRIPTS/wait-signal.sh --name "agent:${AGENT_A}:done" --timeout 300

# 4. Agent-A 결과를 Agent-B에 전달
bash $SCRIPTS/send-message.sh \
  --to "$AGENT_B" \
  --type "peer-request" \
  --payload "{\"task_description\":\"Agent-A 결과 참조하여 Service 구현 시작\",\"artifacts\":[\"$(cat ~/.claude/cmux-agent-ipc/$SESSION/outbox/$AGENT_A.result.json | jq -r '.payload.artifacts[]')\"]}" \
  --signal

# 5. Agent-B 완료 대기
bash $SCRIPTS/wait-signal.sh --name "agent:${AGENT_B}:done" --timeout 300

# 6. 정리
bash $SCRIPTS/cleanup-session.sh --close-panes
```

---

## 아키텍처

### 전체 구조

```
┌────────────────────────────────────────────────────────────────┐
│                      cmux Terminal                              │
│                                                                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ Orchestrator  │  │  Agent-A     │  │  Agent-B     │         │
│  │ (Main Claude) │  │ (Claude #2)  │  │ (Claude #3)  │         │
│  │              │  │              │  │              │         │
│  │  Plan        │  │  Role:       │  │  Role:       │         │
│  │  Spawn       │  │  backend-    │  │  backend-    │         │
│  │  Execute     │  │  model       │  │  service     │         │
│  │  Collect     │  │              │  │              │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                 │                 │                  │
│         └────────┬────────┴────────┬────────┘                  │
│                  │                 │                            │
│         ┌────────▼─────────────────▼────────┐                  │
│         │     File-based IPC Message Bus     │                  │
│         │  ~/.claude/cmux-agent-ipc/{session}/    │                  │
│         │                                    │                  │
│         │  registry/  inbox/  outbox/        │                  │
│         │  prompts/   signals/               │                  │
│         └────────────────────────────────────┘                  │
│                           │                                    │
│                  cmux wait-for signals                          │
│              (blocking synchronization)                         │
└────────────────────────────────────────────────────────────────┘
```

### 5-Phase 워크플로우

```
Phase 1: Plan     ─── 작업 분해, 에이전트 역할 결정, 실행 전략(패턴) 선택
    │
    ▼
Phase 2: Spawn    ─── cmux pane 생성, Claude Code 인스턴스 시작, IPC 초기화
    │
    ▼
Phase 3: Execute  ─── 에이전트 실행 모니터링, 시그널 조율, 메시지 라우팅
    │
    ▼
Phase 4: Collect  ─── 결과 수집, 충돌 해결, 통합 보고서 생성
    │
    ▼
Phase 5: Cleanup  ─── IPC 디렉터리 정리, pane 종료 (선택)
```

### IPC 디렉터리 구조

```
~/.claude/cmux-agent-ipc/{session-id}/
├── session.json                    # 세션 메타데이터 (ID, 프로젝트 경로, 설정)
├── events.log                      # 이벤트 로그 (디버깅용)
├── cmux-debug.log                  # cmux 명령 로그
│
├── registry/                       # 에이전트 등록 정보
│   ├── backend-model-a1b2c3d4.json
│   └── backend-service-e5f6g7h8.json
│
├── inbox/                          # 에이전트별 수신 메시지 큐
│   ├── orchestrator/
│   ├── backend-model-a1b2c3d4/
│   │   ├── <uuid>.json            # 메시지 파일
│   │   └── .consumed/             # 처리 완료 메시지
│   └── backend-service-e5f6g7h8/
│
├── outbox/                         # 에이전트 완료 결과
│   ├── backend-model-a1b2c3d4.result.json
│   └── backend-service-e5f6g7h8.result.json
│
├── prompts/                        # 에이전트 시스템 프롬프트 (자동 생성)
│   ├── backend-model-a1b2c3d4.md
│   └── backend-service-e5f6g7h8.md
│
└── signals/                        # 시그널 로그
    └── signal.log
```

### 통신 메커니즘

cmux-agent-teams는 두 가지 통신 메커니즘을 조합합니다:

**1. 파일 기반 메시지 (데이터 전달)**

에이전트 간 구조화된 데이터(작업 내용, 결과, 파일 목록 등)를 JSON 파일로 교환합니다.
`~/.claude/cmux-agent-ipc/` 디렉터리를 사용하며(Claude Code 샌드박스 허용 경로), 원자적 쓰기(`mv`)로 레이스 컨디션을 방지합니다.

```
Agent-A writes → inbox/Agent-B/<uuid>.json
```

**2. cmux wait-for 시그널 (이벤트 알림)**

"메시지가 도착했다", "작업이 완료되었다" 등의 이벤트를 블로킹 시그널로 알립니다.
파일 폴링 없이 즉각적인 반응이 가능합니다.

```
Agent-A: cmux wait-for -S "session:agent:B:peer-msg"  (시그널 전송)
Agent-B: cmux wait-for "session:agent:B:peer-msg"      (블로킹 대기 → 즉시 깨어남)
```

이 조합으로 **파일의 안정성**과 **시그널의 즉시성**을 동시에 얻습니다.

---

## 사용 시나리오

### 시나리오 A: 백엔드 전용 — 레이어별 분업 (Pipeline)

Spring Boot 프로젝트에서 도메인 레이어를 순차적으로 개발합니다.
각 에이전트는 이전 에이전트의 결과물을 참조합니다.

```
Agent-A (backend-model):
  → User.kt, Order.kt, Payment.kt Entity 클래스 설계
  → done signal 전송

Agent-B (backend-service):
  → Agent-A의 Entity를 참조하여 UserService, OrderService 구현
  → done signal 전송

Agent-C (backend-controller):
  → Agent-B의 Service를 참조하여 UserController, OrderController + DTO 작성
  → done signal 전송
```

**실행:**
```bash
> /cmux-agent-teams pipeline "User 도메인: Entity → Service → Controller 순차 개발"
```

이 시나리오에서는 P2P 통신도 효과적입니다. Agent-A가 Entity를 하나씩 완료할 때마다 Agent-B에 즉시 알리면, Agent-B는 전체 완료를 기다리지 않고 바로 Service 구현을 시작할 수 있습니다.

### 시나리오 B: 백엔드 전용 — 독립 도메인 병렬 (Fanout)

서로 의존성이 없는 도메인 모듈을 병렬로 개발합니다.

```
┌─→ Agent-A: 사용자 인증 모듈 (User Entity + AuthService + AuthController)
├─→ Agent-B: 주문 관리 모듈 (Order Entity + OrderService + OrderController)
└─→ Agent-C: 알림 모듈 (Notification Entity + NotificationService + EmailSender)
```

각 에이전트는 독립적으로 실행되므로 가장 빠른 병렬화를 달성합니다.
3개 모듈을 순차 실행하면 180분이지만, 병렬 실행하면 가장 긴 모듈(75분)에 맞춰 완료됩니다.

**실행:**
```bash
> /cmux-agent-teams fanout "3개 독립 모듈 병렬: 인증, 주문, 알림"
```

### 시나리오 C: 프론트엔드 전용 — 컴포넌트 병렬 개발 (Hybrid)

React 프로젝트에서 공통 컴포넌트 → 페이지 컴포넌트를 개발합니다.

```
Stage 1 (Fanout):
  ├─→ Agent-A: 공통 UI 컴포넌트 (Button, Modal, Form, Input)
  └─→ Agent-C: API 클라이언트 훅 (useAuth, useOrders, useNotifications)

Stage 2 (Pipeline, Agent-A 완료 후):
  └─→ Agent-B: 페이지 레이아웃 (Header, Sidebar, Dashboard) — Agent-A 컴포넌트 사용
```

Agent-A와 Agent-C는 독립적이므로 병렬 실행. Agent-B는 Agent-A의 공통 컴포넌트가 필요하므로 Agent-A 완료 후 시작.

**실행:**
```bash
> /cmux-agent-teams hybrid "프론트엔드 개발: 공통UI∥API훅 → 페이지 레이아웃"
```

### 시나리오 D: 풀스택 파이프라인 (Hybrid)

API 설계부터 프론트엔드 연동, 테스트까지 풀스택 파이프라인입니다.

```
Stage 1 (Fanout — 설계):
  ├─→ Agent-API: OpenAPI Spec 설계
  └─→ Agent-DB: DB 스키마 설계 (ERD + Migration)

Stage 2 (Pipeline — 백엔드 구현):
  └─→ Agent-BE: API Spec + DB Schema 기반 백엔드 구현

Stage 3 (Pipeline — 프론트엔드 연동):
  └─→ Agent-FE: API 연동 코드 작성

Stage 4 (Fanout — 검증):
  ├─→ Agent-TEST: 테스트 코드 작성
  └─→ Agent-REVIEW: 코드 리뷰
```

**실행:**
```bash
> /cmux-agent-teams hybrid "풀스택: API설계∥DB설계 → 백엔드 → 프론트 → 테스트∥리뷰"
```

### 시나리오 E: 레거시 프로젝트 마이그레이션

기존 코드를 분석하고 마이그레이션하는 워크플로우입니다.

```
Stage 1 (Fanout — 분석):
  ├─→ Agent-A: 기존 코드 구조 분석 + 의존성 그래프 생성
  └─→ Agent-B: DB 스키마 분석 + 마이그레이션 영향도 평가

Stage 2 (Pipeline — 계획):
  └─→ Agent-C: 분석 결과 기반 마이그레이션 계획 수립

Stage 3 (Pipeline — 실행):
  └─→ Agent-D: 마이그레이션 스크립트 작성 + 코드 리팩토링

Stage 4 (Pipeline — 검증):
  └─→ Agent-E: 마이그레이션 테스트 + 회귀 테스트
```

레거시 프로젝트는 `--cwd` 옵션으로 프로젝트 경로만 지정하면 됩니다. Expert skill이 없어도 커스텀 역할로 동작합니다.

**실행:**
```bash
> /cmux-agent-teams hybrid "레거시 마이그레이션: 코드분석∥DB분석 → 계획 → 실행 → 검증"
```

### 시나리오 F: 단일 백엔드 — CRUD + 테스트 가속화 (P2P)

API 엔드포인트를 하나씩 구현하면서 동시에 테스트를 작성하는 P2P 패턴입니다.

```
Agent-A (CRUD 구현):                    Agent-B (테스트 작성):
  → User API 구현                         (대기)
  → peer-msg: "User API 완료" ──────→    → User API 테스트 작성
  → Order API 구현                        → (User 테스트 진행 중)
  → peer-msg: "Order API 완료" ─────→    → Order API 테스트 작성
  → Payment API 구현                      → (Order 테스트 진행 중)
  → peer-msg: "Payment API 완료" ───→    → Payment API 테스트 작성
  → done                                 → done
```

Agent-A가 API를 하나 완료할 때마다 P2P로 Agent-B에 알립니다. Agent-B는 전체 완료를 기다리지 않고 즉시 테스트 작성을 시작합니다. 이 파이프라이닝 효과로 전체 시간이 크게 단축됩니다.

**실행:**
```bash
> /cmux-agent-teams p2p "CRUD API 구현(10 endpoints) + 즉시 테스트 작성"
```

---

## 실행 패턴

### Pipeline (순차 파이프라인)

이전 에이전트의 결과가 다음 에이전트의 입력이 되는 순차 실행입니다.

```
Agent-A ──done──→ Orchestrator ──task+result──→ Agent-B ──done──→ ...
```

**적합한 경우:**
- 레이어별 분업 (Entity → Service → Controller)
- API 설계 → 구현 → 연동
- 데이터 변환 파이프라인

**시그널 흐름:**
```
{session}:agent:{A}:done  →  Orchestrator reads outbox/A  →  sends to B  →  {session}:agent:{B}:done
```

### Fanout (병렬 분산)

독립적인 에이전트를 동시에 실행합니다.

```
Orchestrator ──spawn──→ Agent-A ─┐
             ──spawn──→ Agent-B ─┤──all-done──→ Collect
             ──spawn──→ Agent-C ─┘
```

**적합한 경우:**
- 독립 도메인 모듈 개발
- 코드 리뷰 + 성능 분석 병렬
- 여러 파일/디렉터리의 독립 작업

### Feedback (반복 루프)

설계 → 리뷰 → 수정을 반복합니다.

```
Agent-A (설계) → Agent-B (리뷰) ──issues?──→ Agent-A (수정) → Agent-B (재리뷰)
                                  └─ no ──→ Complete
```

**적합한 경우:**
- API 설계 + 코드 리뷰
- 품질 기준 충족까지 반복
- 최대 반복 횟수: 2회 (기본)

### Hybrid (혼합)

여러 패턴을 스테이지별로 조합합니다.

```
Fanout Stage → Pipeline Stage → Fanout Stage
```

**적합한 경우:**
- 분석(병렬) → 구현(순차) → 검증(병렬)
- 복잡한 프로젝트의 대부분의 경우

### P2P (Peer-to-Peer)

에이전트가 오케스트레이터 없이 직접 소통합니다.

```
Agent-A ──peer-msg──→ Agent-B ──peer-msg──→ Agent-C
```

**적합한 경우:**
- 같은 레이어 내 세밀한 협업
- CRUD + 테스트 실시간 파이프라이닝
- 에이전트 자율 조율

---

## IPC 프로토콜

### 개요

cmux-agent-teams의 IPC는 **파일 기반 메시지**와 **cmux wait-for 시그널**을 조합합니다.

- **파일**: 구조화된 데이터(JSON)를 안정적으로 전달. 원자적 쓰기(`mv`)로 레이스 컨디션 방지.
- **시그널**: 이벤트 알림을 즉시 전달. 파일 폴링 없이 블로킹 대기 → 즉시 반응.

### 통신 모드

| 모드 | 경로 | 설명 |
|------|------|------|
| **orchestrated** | Agent → outbox → Orchestrator → inbox → Agent | 오케스트레이터가 중개 (기본) |
| **peer-to-peer** | Agent → inbox/다른Agent/ (직접) | 에이전트 간 직접 통신 |
| **broadcast** | Agent → inbox/모든Agent/ (복사) | 전체 에이전트에 발행 |

### 원자적 쓰기

모든 파일 쓰기는 원자적으로 수행됩니다:

```bash
# 1. 임시 파일에 쓰기
echo "$content" > "${target}.tmp.$$"
# 2. 원자적 이동 (같은 파일 시스템 내 mv는 원자적)
mv "${target}.tmp.$$" "$target"
```

이렇게 하면 읽는 쪽에서 절반만 쓰인 파일을 읽는 문제가 발생하지 않습니다.

---

## 스크립트 레퍼런스

모든 스크립트는 `skills/cmux-agent-teams/scripts/` 디렉터리에 있습니다.

### init-session.sh

IPC 세션을 초기화합니다. 모든 다른 스크립트보다 먼저 실행해야 합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `init-session.sh [--cwd <path>] [--session <id>]` |
| **출력** | session-id (stdout) |
| **부작용** | `~/.claude/cmux-agent-ipc/{session-id}/` 디렉터리 생성 |
| **종료코드** | 0: 성공, 1: jq/cmux 없음 |

| 인자 | 기본값 | 설명 |
|------|--------|------|
| `--cwd` | `$PWD` | 프로젝트 디렉터리 |
| `--session` | 자동 생성 | 커스텀 세션 ID |

**예시:**
```bash
SESSION=$(bash init-session.sh --cwd /path/to/project)
export CMUX_AGENT_SESSION=$SESSION
```

---

### spawn-agent.sh

cmux pane을 생성하고 Claude Code 에이전트를 실행합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `spawn-agent.sh --role <name> --task <desc> [options]` |
| **출력** | agent-id (stdout) |
| **부작용** | cmux pane 생성, registry/inbox/prompts 파일 생성, Claude Code 실행 |
| **종료코드** | 0: 성공, 1: 인자 오류/IPC 없음, 2: pane 생성 실패 |

| 인자 | 필수 | 기본값 | 설명 |
|------|------|--------|------|
| `--role` | O | - | 에이전트 역할 (자유 텍스트) |
| `--task` | O | - | 작업 설명 |
| `--direction` | - | `right` | split 방향 (right/down/left/up) |
| `--cwd` | - | `$PWD` | 작업 디렉터리 |
| `--plugin-dir` | - | (없음) | Claude Code skill 플러그인 경로 |
| `--session` | - | `$CMUX_AGENT_SESSION` | 세션 ID |
| `--peers` | - | (없음) | P2P 대상 (쉼표 구분) |
| `--agent-id` | - | 자동 생성 | 커스텀 에이전트 ID |
| `--timeout` | - | `300` | 타임아웃 (초) |
| `--model` | - | (없음) | Claude 모델 |

**역할 지정 방식:**

```bash
# 기존 Expert Skill 사용
spawn-agent.sh --role "sub-kopring-engineer" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer \
  --task "UserService 구현"

# 커스텀 역할 (skill 없이 — 레거시 프로젝트에 적합)
spawn-agent.sh --role "database-migration" \
  --task "Flyway 마이그레이션 스크립트 작성" \
  --cwd /path/to/legacy-project

# P2P 대상 지정
spawn-agent.sh --role "backend-service" \
  --task "Service 구현" \
  --peers "backend-model-a1b2,backend-controller-c3d4"
```

---

### send-message.sh

에이전트 inbox에 메시지를 전송합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `send-message.sh --to <id\|broadcast> --type <type> --payload <json>` |
| **출력** | message-id (stdout) |
| **종료코드** | 0: 성공, 1: 인자 오류 |

| 인자 | 필수 | 설명 |
|------|------|------|
| `--to` | O | 수신자 agent-id 또는 "broadcast" |
| `--type` | O | 메시지 유형 (task/result/peer-request/peer-response/signal/error) |
| `--payload` | O | JSON 문자열 |
| `--from` | - | 발신자 (기본: "orchestrator") |
| `--signal` | - | 메시지 전송 후 cmux 시그널도 전송 |

---

### read-messages.sh

에이전트 inbox에서 메시지를 읽습니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `read-messages.sh --agent <id> [--consume] [--type <filter>] [--latest]` |
| **출력** | JSON 배열 (stdout) |
| **종료코드** | 0: 항상 성공 (빈 배열 포함) |

| 인자 | 설명 |
|------|------|
| `--agent` | 대상 에이전트 ID |
| `--consume` | 읽은 메시지를 .consumed/로 이동 |
| `--type` | 특정 타입만 필터링 |
| `--latest` | 가장 최근 메시지 1개만 |

---

### signal-agent.sh

cmux wait-for 시그널을 전송합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `signal-agent.sh --name <signal-name>` |
| **종료코드** | 0: 성공, 1: 실패 |

세션 prefix가 없으면 자동으로 `{session-id}:` prefix를 추가합니다.

---

### wait-signal.sh

cmux wait-for 시그널을 대기합니다 (블로킹).

| 항목 | 내용 |
|------|------|
| **사용법** | `wait-signal.sh --name <signal-name> [--timeout <sec>]` |
| **종료코드** | 0: 시그널 수신, 1: 타임아웃 |

| 인자 | 기본값 | 설명 |
|------|--------|------|
| `--name` | (필수) | 대기할 시그널 이름 |
| `--timeout` | `300` | 타임아웃 (초) |

---

### check-agent-health.sh

에이전트 상태를 확인합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `check-agent-health.sh --agent <id>` |
| **출력** | JSON `{agent_id, status, surface_id, last_output}` |

**status 값:**
- `running` — 실행 중
- `completed` — 완료 (outbox에 결과 존재 또는 Claude 종료 감지)
- `failed` — 에러 패턴 감지 또는 result status가 failed
- `not_found` — registry에 없음

---

### list-agents.sh

등록된 에이전트 목록을 조회합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `list-agents.sh [--role <filter>] [--status <filter>]` |
| **출력** | JSON 배열 (에이전트 정보 + has_result, inbox_pending 추가) |

---

### monitor-agents.sh

전체 에이전트 상태를 모니터링합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `monitor-agents.sh [--interval <sec>] [--once]` |
| **출력** | 주기적 JSON summary (total, running, completed, failed) |
| **종료 조건** | 모든 에이전트 완료 시 자동 종료 |

---

### cleanup-session.sh

IPC 세션을 정리합니다.

| 항목 | 내용 |
|------|------|
| **사용법** | `cleanup-session.sh [--close-panes] [--auto]` |
| **부작용** | IPC 디렉터리 삭제, (선택) 에이전트 pane 닫기 |

| 인자 | 설명 |
|------|------|
| `--close-panes` | 에이전트 cmux pane도 닫기 |
| `--auto` | Stop 훅에서 호출 시 (확인 없이 정리, close-panes 포함) |

---

## 메시지 포맷 레퍼런스

### 메시지 공통 구조

```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "type": "task",
  "from": "orchestrator",
  "to": "backend-model-a1b2c3d4",
  "timestamp": "2026-04-04T10:30:00Z",
  "payload": { ... },
  "metadata": { ... }
}
```

### 필드별 설명

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `id` | string (UUID) | O | 메시지 고유 ID. 파일명으로도 사용 (`{id}.json`) |
| `type` | string | O | 메시지 유형 (아래 표 참조) |
| `from` | string | O | 발신자. `"orchestrator"` 또는 에이전트 ID |
| `to` | string | O | 수신자. 에이전트 ID, `"orchestrator"`, `"broadcast"` |
| `timestamp` | string | O | ISO-8601 UTC 시각 |
| `payload` | object | O | 메시지 본문 (type에 따라 구조 다름) |
| `metadata` | object | - | 부가 정보 (session_id, sequence, reply_to 등) |

### type별 payload 구조

**`task` — 작업 할당**

| payload 필드 | 타입 | 설명 |
|-------------|------|------|
| `task_description` | string | 수행할 작업 설명 |
| `context.project_root` | string | 프로젝트 루트 경로 |
| `context.dependency_results` | array | 이전 에이전트 결과 목록 |
| `context.constraints` | string | 제약 사항 |
| `peers` | array | P2P 통신 가능 에이전트 목록 |
| `timeout_seconds` | number | 타임아웃 |

**`result` — 결과 보고**

| payload 필드 | 타입 | 설명 |
|-------------|------|------|
| `status` | string | `"completed"`, `"partial"`, `"failed"` |
| `result_summary` | string | 작업 결과 요약 |
| `artifacts` | array | 생성/수정한 파일 절대 경로 목록 |
| `metrics` | object | 수치 지표 (파일 수, 소요 시간 등) |
| `error` | string\|null | 에러 메시지 (실패 시) |

**`peer-request` / `peer-response` — P2P 통신**

| payload 필드 | 타입 | 설명 |
|-------------|------|------|
| `task_description` | string | 요청/응답 내용 |
| `artifacts` | array | 참조 파일 경로 |
| `status` | string | `"pending"` (request), `"completed"` (response) |
| `reply_to` | string | 원본 peer-request의 id (response일 때) |

---

## 시그널 네이밍 컨벤션

모든 시그널은 `{session-id}:` prefix로 시작하여 세션 간 충돌을 방지합니다.
스크립트에서 세션 prefix 없이 이름만 전달하면 자동으로 prefix가 추가됩니다.

| 시그널 패턴 | 발신자 | 설명 |
|-------------|--------|------|
| `{session}:agent:{id}:ready` | 에이전트 | 초기화 완료, 작업 수신 가능 |
| `{session}:agent:{id}:done` | 에이전트 | 작업 완료, outbox에 결과 존재 |
| `{session}:agent:{id}:error` | 에이전트 | 에러 발생 |
| `{session}:agent:{id}:peer-msg` | 발신 에이전트 | P2P 메시지가 수신자 inbox에 도착 |
| `{session}:stage:{name}:done` | 오케스트레이터 | Pipeline 스테이지 완료 |
| `{session}:all-done` | 모니터 | 모든 에이전트 완료 |
| `{session}:broadcast:{type}` | 발신자 | 브로드캐스트 메시지 전송 알림 |

**사용 예시:**

```bash
# 시그널 전송 (세션 prefix 자동)
bash signal-agent.sh --name "agent:backend-a1b2:done"
# → 실제 시그널: "abc123:agent:backend-a1b2:done"

# 시그널 대기
bash wait-signal.sh --name "agent:backend-a1b2:done" --timeout 300
```

---

## Peer-to-Peer 통신

### 개요

P2P 통신은 에이전트가 오케스트레이터를 거치지 않고 직접 다른 에이전트와 소통하는 방식입니다.
같은 도메인 에이전트 간 빠른 협업에 적합합니다.

### P2P 에이전트 설정

`spawn-agent.sh`의 `--peers` 옵션으로 P2P 대상을 지정합니다:

```bash
AGENT_A=$(bash spawn-agent.sh --role "backend-model" --task "Entity 설계" \
  --peers "$AGENT_B_ID")

AGENT_B=$(bash spawn-agent.sh --role "backend-service" --task "Service 구현" \
  --peers "$AGENT_A_ID")
```

`--peers`로 지정된 에이전트 정보가 시스템 프롬프트에 포함되어,
에이전트가 상대방의 inbox에 직접 메시지를 쓰고 시그널을 보낼 수 있습니다.

### P2P 통신 흐름

```
Backend Agent-A (모델)              Backend Agent-B (서비스)
    │                                   │
    ├── Entity 정의 (User.kt)          │
    ├── outbox에 중간 결과 쓰기         │
    ├── Agent-B inbox에 peer-request:   │
    │   "User Entity 완료, 참조하세요"   │
    ├── cmux wait-for -S               │
    │   "...:agent:B:peer-msg" ────────┤
    │                                   ├── peer-msg 시그널 수신
    ├── Order Entity 계속 작업          ├── inbox에서 peer-request 읽기
    │                                   ├── Agent-A outbox에서 User.kt 확인
    │                                   ├── UserService 구현 시작
    │   ...                             │   ...
```

### 에이전트가 다른 에이전트를 발견하는 방법

에이전트는 registry 디렉터리를 읽어서 다른 에이전트를 발견합니다:

```bash
# 모든 에이전트 목록
ls ~/.claude/cmux-agent-ipc/${SESSION}/registry/

# 특정 역할의 에이전트 찾기
cat ~/.claude/cmux-agent-ipc/${SESSION}/registry/*.json | jq 'select(.role | contains("backend"))'
```

---

## 서브에이전트 (teammateMode)

### 개요

cmux-agent-teams가 생성하는 각 에이전트는 단순한 단일 Claude 세션이 아닙니다. 각 에이전트는 Claude Code의 **Agent Teams** 기능이 활성화된 상태로 실행되어, 자신의 작업을 더 작은 서브에이전트로 분할하여 병렬 처리할 수 있습니다.

이를 통해 **2단계 병렬화**가 가능합니다:
- **1단계**: cmux-agent-teams가 작업을 여러 에이전트로 분할 (cmux split pane)
- **2단계**: 각 에이전트가 내부적으로 더 작은 서브에이전트를 스폰 (in-process)

### 동작 구조

```
cmux-agent-teams (오케스트레이터)
│
├── [cmux split] Agent: backend-model
│   └── Claude Code (teammateMode: in-process)
│       ├── Sub-agent: User Entity 설계
│       ├── Sub-agent: Order Entity 설계
│       └── Sub-agent: Payment Entity 설계
│
├── [cmux split] Agent: backend-service
│   └── Claude Code (teammateMode: in-process)
│       ├── Sub-agent: UserService 구현
│       ├── Sub-agent: OrderService 구현
│       └── Sub-agent: 통합 테스트 작성
│
└── [cmux split] Agent: frontend
    └── Claude Code (teammateMode: in-process)
        ├── Sub-agent: API 클라이언트 훅 생성
        ├── Sub-agent: 페이지 컴포넌트 작성
        └── Sub-agent: 스토어 설정
```

### 자동 설정

각 에이전트 생성 시 `spawn-agent.sh`가 자동으로 다음 설정을 포함한 `settings.json`을 생성하여 전달합니다:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "teammateMode": "in-process",
  "permissions": {
    "allow": ["Agent", "Bash", "Read", "Write", "Edit", "Glob", "Grep"]
  }
}
```

| 설정 | 값 | 설명 |
|------|-----|------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Claude Code Agent Teams 기능 활성화 |
| `teammateMode` | `"in-process"` | 서브에이전트가 같은 터미널 내에서 실행 (별도 터미널 불필요) |
| `permissions.allow` | `["Agent", ...]` | Agent 도구를 포함한 주요 도구 사용 허용 |

### teammateMode 옵션

| 모드 | 동작 | cmux-agent-teams 기본값 |
|------|------|------------------------|
| `in-process` | 서브에이전트가 같은 터미널에서 실행 | **O (기본)** |
| `tmux` | 서브에이전트가 tmux/iTerm2 split pane에서 실행 | - |
| `auto` | 환경에 따라 자동 선택 | - |

cmux-agent-teams에서는 `in-process`가 기본값입니다. 각 에이전트가 이미 별도 cmux pane에서 실행되고 있으므로, 서브에이전트까지 추가 pane을 만들면 화면이 과도하게 분할됩니다. `in-process`는 서브에이전트를 같은 pane 내에서 조용히 실행합니다.

### 언제 서브에이전트가 유용한가

각 에이전트의 시스템 프롬프트에 "작업이 크면 Agent 도구로 서브에이전트를 적극 활용하세요"라는 안내가 포함됩니다. Claude는 다음과 같은 상황에서 자동으로 서브에이전트를 생성합니다:

**파일 탐색/분석이 필요할 때:**
- 기존 코드베이스를 분석하면서 동시에 새 코드를 작성
- 여러 디렉터리의 패턴을 조사하여 일관성 있는 코드 생성

**독립적인 서브태스크가 있을 때:**
- Entity 3개를 각각 서브에이전트에 위임하여 병렬 생성
- 구현과 테스트를 동시에 진행

**복잡한 리서치가 필요할 때:**
- API 문서를 조사하는 서브에이전트 + 코드를 작성하는 메인 에이전트
- 의존성 분석 서브에이전트 + 마이그레이션 스크립트 작성 메인 에이전트

### 예시: 백엔드 에이전트의 서브에이전트 활용

cmux-agent-teams가 `backend-model` 에이전트를 스폰하면, 해당 에이전트 내부에서:

```
[Agent: backend-model] cmux split pane에서 실행 중

Claude: "Entity 3개를 설계해야 합니다. 서브에이전트를 활용하겠습니다."

  → Sub-agent (Explore): "기존 프로젝트의 Entity 패턴 분석"
    ← 결과: "JPA + Kotlin data class 패턴 사용 중"

  → Sub-agent (general-purpose): "User Entity 생성"
    ← 결과: User.kt 생성 완료

  → Sub-agent (general-purpose): "Order Entity 생성"  
    ← 결과: Order.kt 생성 완료

Claude: "모든 Entity 생성 완료. 결과를 outbox에 기록합니다."
  → outbox에 result.json 작성
  → 백그라운드 모니터가 감지 → 시그널 전송
  → 오케스트레이터가 다음 파이프라인 단계로 진행
```

이 과정이 cmux split pane에서 실시간으로 보입니다.

---

## 외부 스킬 연동

### 독립 사용 (기본)

cmux-agent-teams는 외부 스킬 없이도 완전히 동작합니다. 어떤 프로젝트에서든 커스텀 역할로 에이전트를 실행할 수 있습니다.

### Expert Skill과 함께 사용

기존 Claude Code skill 플러그인이 있다면 `--plugin-dir`로 연결합니다:

```bash
spawn-agent.sh --role "sub-kopring-engineer" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer \
  --task "UserService 구현"
```

이 경우 해당 에이전트는 sub-kopring-engineer의 SKILL.md + resources를 사용하면서,
추가로 IPC 시스템 프롬프트도 함께 적용됩니다.

### sub-team-lead 연동

sub-team-lead 플러그인의 Coordinate phase에서 cmux-agent-teams를 호출하면
기존 순차 실행을 병렬 실행으로 전환할 수 있습니다.

```xml
<sister-skill-invoke skill="cmux-agent-teams">
  <caller>sub-team-lead</caller>
  <phase>coordinate</phase>
  <trigger>multi-expert-parallel-via-cmux</trigger>
  <targets>{ "pattern": "pipeline", "agents": [...] }</targets>
</sister-skill-invoke>
```

### cmux 미설치 시 Fallback

cmux가 없는 환경에서는 기존 sister-skill invoke 방식으로 동작합니다.

---

## 제한사항 및 트러블슈팅

### 제한사항

| 항목 | 제한 | 이유 |
|------|------|------|
| 최대 동시 에이전트 | 6개 (권장) | 터미널 공간 + 시스템 리소스 |
| 기본 타임아웃 | 300초 (5분) | 개별 에이전트 |
| 최대 피드백 반복 | 2회 | 무한 루프 방지 |
| IPC 디렉터리 | `~/.claude/cmux-agent-ipc/` | Claude Code 샌드박스 허용 경로 |
| cmux 필수 | cmux 앱 실행 중이어야 함 | cmux socket 통신 |

### 트러블슈팅

**Q: "cmux가 설치되어 있지 않습니다" 에러**

cmux 앱이 설치되어 있고 실행 중인지 확인하세요:
```bash
cmux version
cmux ping
```

**Q: 에이전트가 시작되지 않음**

cmux pane이 생성되었는지 확인:
```bash
cmux tree
```

에이전트 등록 정보 확인:
```bash
cat ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/registry/*.json | jq .
```

**Q: 시그널 타임아웃**

에이전트가 실제로 실행 중인지 `read-screen`으로 확인:
```bash
cmux read-screen --surface <surface-id> --lines 20
```

**Q: IPC 디렉터리가 남아있음**

수동 정리:
```bash
bash cleanup-session.sh --session <session-id> --close-panes
# 또는 전체 정리
rm -rf ~/.claude/cmux-agent-ipc/
```

**Q: 에이전트가 다른 에이전트의 결과를 읽지 못함**

outbox 파일이 존재하는지 확인:
```bash
ls ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/outbox/
```

시그널이 정상 전송되었는지 확인:
```bash
cat ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/signals/signal.log
```

---

## 라이선스

MIT License. [LICENSE](./LICENSE) 파일 참조.
