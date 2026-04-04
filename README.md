# cmux-agent-teams

**🇺🇸 English** | [🇰🇷 한국어](README.ko.md)

**A cmux-based multi-agent parallel execution plugin** — Run multiple Claude Code instances simultaneously across cmux terminal panes, with file-based IPC and signal synchronization for real-time collaboration between agents.

Backend-to-backend, frontend-to-frontend, full-stack pipelines, legacy project migrations — any combination works.

---

### Fanout — Parallel Execution Demo

![Fanout parallel execution demo](docs/fanout.gif)

### Pipeline — Sequential Pipeline Demo

![Pipeline sequential pipeline demo](docs/pipeline.gif)

---

---

## Table of Contents

- [Why Use This?](#why-use-this)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Use Cases](#use-cases)
- [Execution Patterns](#execution-patterns)
- [IPC Protocol](#ipc-protocol)
- [Script Reference](#script-reference)
- [Message Format Reference](#message-format-reference)
- [Signal Naming Convention](#signal-naming-convention)
- [Peer-to-Peer Communication](#peer-to-peer-communication)
- [Sub-agents (teammateMode)](#sub-agents-teammatemode)
- [External Skill Integration](#external-skill-integration)
- [Limitations & Troubleshooting](#limitations--troubleshooting)
- [License](#license)

---

## Why Use This?

### The Problem: Single-Session Bottleneck in Claude Code

Claude Code is powerful, but each session can only handle one task at a time. For complex projects, this becomes a serious bottleneck.

**Example: A typical API development workflow**

```
Sequential execution (traditional):
  Entity design    [====]                              30 min
  Service impl           [========]                   60 min
  Controller impl                  [======]           45 min
  Frontend integration                    [========]  60 min
  Test writing                                  [====] 30 min
  ─────────────────────────────────────────────────────
  Total: 225 min (3h 45m)
```

### The Solution: Multi-Agent Parallel Execution

With cmux-agent-teams, independent tasks run in parallel, and tasks with dependencies are connected via a signal-based pipeline.

```
Parallel execution (cmux-agent-teams):
  Entity design    [====]
  Service impl           [========]
  Controller impl                  [======]
  Frontend integration                    [========]
  Test writing           [====][====][====][====]  ← P2P start as each API completes
  ─────────────────────────────────────────────
  Total: ~150 min (2h 30m) — 33% faster
```

The gains are even greater when developing independent domains in parallel:

```
Parallel execution (independent modules):
  Auth module      [===========]                60 min
  Order module     [===============]            75 min  ← longest task sets the total
  Notification     [========]                   45 min
  ─────────────────────────────────
  Total: 75 min (vs. 180 min sequential → 58% faster)
```

### How It Differs from Agent Tool

Claude Code's built-in Agent Tool can run sub-agents too, but has fundamental limitations:

| Feature | Agent Tool | cmux-agent-teams |
|---------|-----------|------------------|
| Execution model | Sub-tasks within a single process | Separate Claude instances in independent terminals |
| Inter-agent communication | Not possible (results only) | Real-time P2P messages + signals |
| Intermediate result sharing | Not possible | Instant sharing via outbox/inbox |
| Progress monitoring | Wait until completion | Real-time monitoring with `read-screen` |
| Agent autonomy | Limited | Independent execution, own tool access |
| Plugin support | Not available | Each agent can load its own plugins |

### Works with Any Project

cmux-agent-teams makes no assumptions about your framework or project structure.

- Spring Boot, React, Next.js, Go, Python, Ruby — any stack works
- Drop it into legacy projects without changes
- Auto-detects CLAUDE.md, package.json, build.gradle and injects context into agents
- Works with custom roles even without Expert skill plugins

---

## Requirements

| Requirement | Version | Check |
|-------------|---------|-------|
| **cmux** | latest | `cmux version` |
| **Claude Code** | latest | `claude --version` |
| **bash** | 4.0+ | `bash --version` |
| **jq** | 1.6+ | `jq --version` |

Install cmux at https://cmux.dev

---

## Installation

### Option 1: Remote Install from GitHub (Recommended)

Install directly from GitHub through Claude Code's plugin marketplace system.
No need to clone or manage files manually — updates are picked up automatically.

```bash
# 1. Register the GitHub repo in the marketplace
/plugin marketplace add hungrytech/cmux-agent-teams

# 2. Install the plugin
/plugin install cmux-agent-teams@cmux-agent-teams
```

Or directly from the CLI:

```bash
claude plugin marketplace add hungrytech/cmux-agent-teams
claude plugin install cmux-agent-teams@cmux-agent-teams
```

#### Specifying Scope

```bash
# For personal use only (default)
/plugin install cmux-agent-teams@cmux-agent-teams --scope user

# For the entire project team (recorded in .claude/settings.json)
/plugin install cmux-agent-teams@cmux-agent-teams --scope project
```

With `--scope project`, plugin info is recorded in `.claude/settings.json`,
so the plugin activates automatically when any team member starts Claude Code in that project.

#### Pinning a Specific Version

```bash
# Pin to a specific tag or branch
/plugin marketplace add https://github.com/hungrytech/cmux-agent-teams.git#v1.0.0
```

#### Pre-configuring with settings.json

Add directly to your project's `.claude/settings.json` to enable it automatically for the whole team:

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

### Option 2: Git Clone + Local Install

Best for local customization or when you want to modify the code.

```bash
# 1. Clone the repo
git clone https://github.com/hungrytech/cmux-agent-teams.git ~/cmux-agent-teams

# 2. Register as a local marketplace entry
/plugin marketplace add ~/cmux-agent-teams
/plugin install cmux-agent-teams@cmux-agent-teams
```

### Option 3: Direct Reference with --plugin-dir

Best for one-time use or testing during development without a full install.

```bash
# Point directly to the plugin directory (the actual plugin path under plugins/)
claude --plugin-dir ~/cmux-agent-teams/plugins/cmux-agent-teams
```

### Verifying Installation

```bash
# After starting Claude Code in a cmux terminal
> /cmux-agent-teams --help

# List installed plugins
/plugin list
```

---

## Usage

```
/cmux-agent-teams [pipeline|fanout|feedback|hybrid|p2p] [--sub-agents] <task-description>
```

| Argument | Required | Description |
|----------|----------|-------------|
| `pipeline\|fanout\|feedback\|hybrid\|p2p` | Yes | Execution pattern |
| `--sub-agents` | No | Enable sub-agent spawning for each agent (teammateMode: in-process) |
| `<task-description>` | Yes | Task description in natural language |

### Global Option: `--sub-agents`

Adding `--sub-agents` activates Claude Code's Agent Teams feature on every spawned agent. Each agent can then split its own work into smaller sub-agents, achieving **two-level parallelization**.

```bash
# Default (no sub-agents)
> /cmux-agent-teams pipeline "Entity design → Service impl → Controller"

# With sub-agents enabled
> /cmux-agent-teams pipeline --sub-agents "Entity design → Service impl → Controller"
```

See the [Sub-agents (teammateMode)](#sub-agents-teammatemode) section for details.

---

## Quick Start

### Example 1: Backend API Development (Pipeline)

```bash
# Navigate to your project in a cmux terminal
cd /path/to/your-spring-project

# Start Claude Code
claude --plugin-dir ~/cmux-agent-teams

# Invoke the skill
> /cmux-agent-teams pipeline "User domain API: Entity design → Service impl → Controller"

# With sub-agents (each agent spawns its own internal sub-agents)
> /cmux-agent-teams pipeline --sub-agents "User domain API: Entity design → Service impl → Controller"
```

Claude will automatically:
1. Break the task into 3 agents
2. Create 3 cmux panes
3. Run Entity agent → completion signal → Service agent → ... in sequence
4. Generate a consolidated report once all agents complete

Adding `--sub-agents` lets each agent use Claude Code's Agent Teams (teammateMode: in-process) to parallelize its own work into smaller sub-agents — most effective for complex tasks.

### Example 2: Parallel Independent Module Development (Fanout)

```bash
> /cmux-agent-teams fanout "3 independent modules in parallel: Auth, Order, Notification"

# With sub-agents
> /cmux-agent-teams fanout --sub-agents "3 independent modules in parallel: Auth, Order, Notification"
```

### Example 3: Manual Script Execution

```bash
# 1. Initialize a session
SESSION=$(bash ~/cmux-agent-teams/plugins/cmux-agent-teams/skills/cmux-agent-teams/scripts/init-session.sh)
export CMUX_AGENT_SESSION=$SESSION

# 2. Create agents
SCRIPTS=~/cmux-agent-teams/plugins/cmux-agent-teams/skills/cmux-agent-teams/scripts

# Omitting --direction uses auto layout: Agent-A=top, Agent-B=right, orchestrator=bottom
AGENT_A=$(bash $SCRIPTS/spawn-agent.sh \
  --role "backend-model" \
  --task "Design User, Order, Payment Entity classes")

AGENT_B=$(bash $SCRIPTS/spawn-agent.sh \
  --role "backend-service" \
  --task "Implement the Service layer" \
  --peers "$AGENT_A")

# 3. Wait for Agent-A to finish
bash $SCRIPTS/wait-signal.sh --name "agent:${AGENT_A}:done" --timeout 300

# 4. Forward Agent-A's result to Agent-B
bash $SCRIPTS/send-message.sh \
  --to "$AGENT_B" \
  --type "peer-request" \
  --payload "{\"task_description\":\"Start Service impl referencing Agent-A result\",\"artifacts\":[\"$(cat ~/.claude/cmux-agent-ipc/$SESSION/outbox/$AGENT_A.result.json | jq -r '.payload.artifacts[]')\"]}" \
  --signal

# 5. Wait for Agent-B to finish
bash $SCRIPTS/wait-signal.sh --name "agent:${AGENT_B}:done" --timeout 300

# 6. Clean up
bash $SCRIPTS/cleanup-session.sh --close-panes
```

---

## Architecture

### Overall Structure

```
┌────────────────────────────────────────────────────────────────┐
│                      cmux Terminal                              │
│                                                                │
│  ┌──────────────┬──────────────┬──────────────┐                │
│  │  Agent-A     │  Agent-B     │  Agent-C     │  ← row 0      │
│  │ (Claude #2)  │ (Claude #3)  │ (Claude #4)  │                │
│  │  backend-    │  backend-    │  backend-    │                │
│  │  model       │  service     │  controller  │                │
│  ├──────────────┼──────────────┼──────────────┤                │
│  │  Agent-D     │  Agent-E     │  Agent-F     │  ← row 1      │
│  │ (Claude #5)  │ (Claude #6)  │ (Claude #7)  │  (agent 4+)   │
│  │  frontend-   │  test-       │  review-     │                │
│  │  api         │  writer      │  code        │                │
│  └──────┬───────┴──────┬───────┴──────┬───────┘                │
│         │              │              │                        │
│  ┌──────┴──────────────┴──────────────┴───────┐                │
│  │ Orchestrator (Main Claude) — pinned bottom  │                │
│  │  Plan → Spawn → Execute → Collect → Cleanup │                │
│  └──────┬─────────────────────────────────────┘                │
│         │                                                      │
│         ┌────────────────────────────────────────┐              │
│         │     File-based IPC Message Bus          │              │
│         │  ~/.claude/cmux-agent-ipc/{session}/    │              │
│         │                                         │              │
│         │  registry/  inbox/  outbox/             │              │
│         │  prompts/   signals/                    │              │
│         └────────────────────────────────────────┘              │
│                           │                                    │
│                  cmux wait-for signals                          │
│              (blocking synchronization)                         │
└────────────────────────────────────────────────────────────────┘

Max 3 agents per row. A new row is created automatically from the 4th agent onward.
```

### 5-Phase Workflow

```
Phase 1: Plan     ─── Decompose tasks, determine agent roles, choose execution pattern
    │
    ▼
Phase 2: Spawn    ─── Create cmux panes, start Claude Code instances, initialize IPC
    │
    ▼
Phase 3: Execute  ─── Monitor agent execution, coordinate signals, route messages
    │
    ▼
Phase 4: Collect  ─── Gather results, resolve conflicts, generate consolidated report
    │
    ▼
Phase 5: Cleanup  ─── Remove IPC directory, close panes (optional)
```

### IPC Directory Structure

```
~/.claude/cmux-agent-ipc/{session-id}/
├── session.json                    # Session metadata (ID, project path, settings)
├── events.log                      # Event log (for debugging)
├── cmux-debug.log                  # cmux command log
│
├── registry/                       # Agent registration info
│   ├── backend-model-a1b2c3d4.json
│   └── backend-service-e5f6g7h8.json
│
├── inbox/                          # Per-agent incoming message queue
│   ├── orchestrator/
│   ├── backend-model-a1b2c3d4/
│   │   ├── <uuid>.json            # Message file
│   │   └── .consumed/             # Processed messages
│   └── backend-service-e5f6g7h8/
│
├── outbox/                         # Agent completion results
│   ├── backend-model-a1b2c3d4.result.json
│   └── backend-service-e5f6g7h8.result.json
│
├── prompts/                        # Agent system prompts (auto-generated)
│   ├── backend-model-a1b2c3d4.md
│   └── backend-service-e5f6g7h8.md
│
└── signals/                        # Signal log
    └── signal.log
```

### Communication Mechanisms

cmux-agent-teams combines two communication mechanisms:

**1. File-based messages (data transfer)**

Structured data (task details, results, file lists, etc.) is exchanged as JSON files between agents.
Uses the `~/.claude/cmux-agent-ipc/` directory (an allowed path within Claude Code's sandbox), with atomic writes (`mv`) to prevent race conditions.

```
Agent-A writes → inbox/Agent-B/<uuid>.json
```

**2. cmux wait-for signals (event notification)**

Events like "a message arrived" or "a task is done" are communicated as blocking signals.
This enables immediate reactions without file polling.

```
Agent-A: cmux wait-for -S "session:agent:B:peer-msg"  (send signal)
Agent-B: cmux wait-for "session:agent:B:peer-msg"      (blocking wait → wakes immediately)
```

This combination gives you both the **reliability of files** and the **immediacy of signals**.

---

## Use Cases

### Scenario A: Backend Only — Layer-by-Layer (Pipeline)

Develop domain layers sequentially in a Spring Boot project.
Each agent references the previous agent's output.

```
Agent-A (backend-model):
  → Design User.kt, Order.kt, Payment.kt Entity classes
  → Send done signal

Agent-B (backend-service):
  → Implement UserService, OrderService referencing Agent-A's Entities
  → Send done signal

Agent-C (backend-controller):
  → Write UserController, OrderController + DTOs referencing Agent-B's Services
  → Send done signal
```

**Run:**
```bash
# Basic
> /cmux-agent-teams pipeline "User domain: Entity → Service → Controller sequential"

# With sub-agents (each agent can spawn internal sub-agents)
> /cmux-agent-teams pipeline --sub-agents "User domain: Entity → Service → Controller sequential"
```

P2P communication is also effective here. As Agent-A finishes each Entity, it can immediately notify Agent-B, so Agent-B starts implementing Services without waiting for full completion.

### Scenario B: Backend Only — Independent Domains in Parallel (Fanout)

Develop domain modules with no dependencies between them in parallel.

```
┌─→ Agent-A: User auth module (User Entity + AuthService + AuthController)
├─→ Agent-B: Order module (Order Entity + OrderService + OrderController)
└─→ Agent-C: Notification module (Notification Entity + NotificationService + EmailSender)
```

Each agent runs independently, achieving maximum parallelization.
Sequential execution of 3 modules would take 180 min; parallel finishes at the longest module (75 min).

**Run:**
```bash
> /cmux-agent-teams fanout "3 independent modules in parallel: Auth, Order, Notification"

# With sub-agents
> /cmux-agent-teams fanout --sub-agents "3 independent modules in parallel: Auth, Order, Notification"
```

### Scenario C: Frontend Only — Component Parallel Development (Hybrid)

Build shared components first, then page components, in a React project.

```
Stage 1 (Fanout):
  ├─→ Agent-A: Common UI components (Button, Modal, Form, Input)
  └─→ Agent-C: API client hooks (useAuth, useOrders, useNotifications)

Stage 2 (Pipeline, after Agent-A completes):
  └─→ Agent-B: Page layouts (Header, Sidebar, Dashboard) — uses Agent-A's components
```

Agent-A and Agent-C run in parallel since they're independent. Agent-B starts only after Agent-A finishes, as it depends on the shared components.

**Run:**
```bash
> /cmux-agent-teams hybrid "Frontend: CommonUI∥APIHooks → PageLayouts"

# With sub-agents
> /cmux-agent-teams hybrid --sub-agents "Frontend: CommonUI∥APIHooks → PageLayouts"
```

### Scenario D: Full-Stack Pipeline (Hybrid)

A complete pipeline from API design through frontend integration and testing.

```
Stage 1 (Fanout — Design):
  ├─→ Agent-API: OpenAPI Spec design
  └─→ Agent-DB: DB schema design (ERD + Migration)

Stage 2 (Pipeline — Backend impl):
  └─→ Agent-BE: Backend implementation from API Spec + DB Schema

Stage 3 (Pipeline — Frontend integration):
  └─→ Agent-FE: Write API integration code

Stage 4 (Fanout — Validation):
  ├─→ Agent-TEST: Write test code
  └─→ Agent-REVIEW: Code review
```

**Run:**
```bash
> /cmux-agent-teams hybrid "Full-stack: APIDesign∥DBDesign → Backend → Frontend → Tests∥Review"

# With sub-agents (recommended — full-stack pipelines are complex)
> /cmux-agent-teams hybrid --sub-agents "Full-stack: APIDesign∥DBDesign → Backend → Frontend → Tests∥Review"
```

### Scenario E: Legacy Project Migration

Analyze and migrate an existing codebase.

```
Stage 1 (Fanout — Analysis):
  ├─→ Agent-A: Analyze existing code structure + generate dependency graph
  └─→ Agent-B: Analyze DB schema + assess migration impact

Stage 2 (Pipeline — Planning):
  └─→ Agent-C: Create migration plan based on analysis results

Stage 3 (Pipeline — Execution):
  └─→ Agent-D: Write migration scripts + refactor code

Stage 4 (Pipeline — Validation):
  └─→ Agent-E: Migration tests + regression tests
```

For legacy projects, just point `--cwd` at the project path. Works with custom roles even without Expert skills.

**Run:**
```bash
> /cmux-agent-teams hybrid "Legacy migration: CodeAnalysis∥DBAnalysis → Plan → Execute → Verify"

# With sub-agents
> /cmux-agent-teams hybrid --sub-agents "Legacy migration: CodeAnalysis∥DBAnalysis → Plan → Execute → Verify"
```

### Scenario F: Single Backend — CRUD + Test Acceleration (P2P)

Implement API endpoints one by one while writing tests in parallel using the P2P pattern.

```
Agent-A (CRUD impl):                    Agent-B (test writing):
  → Implement User API                    (waiting)
  → peer-msg: "User API done" ──────→    → Write User API tests
  → Implement Order API                   → (User tests in progress)
  → peer-msg: "Order API done" ─────→    → Write Order API tests
  → Implement Payment API                 → (Order tests in progress)
  → peer-msg: "Payment API done" ───→    → Write Payment API tests
  → done                                  → done
```

Each time Agent-A finishes an API, it notifies Agent-B via P2P. Agent-B starts writing tests immediately without waiting for everything to finish. This pipelining effect significantly reduces total time.

**Run:**
```bash
> /cmux-agent-teams p2p "CRUD API (10 endpoints) + immediate test writing"

# With sub-agents
> /cmux-agent-teams p2p --sub-agents "CRUD API (10 endpoints) + immediate test writing"
```

---

## Execution Patterns

### Pipeline (Sequential Pipeline)

Sequential execution where each agent's output becomes the next agent's input.

```
Agent-A ──done──→ Orchestrator ──task+result──→ Agent-B ──done──→ ...
```

**Best for:**
- Layer-by-layer separation (Entity → Service → Controller)
- API design → implementation → integration
- Data transformation pipelines

**Signal flow:**
```
{session}:agent:{A}:done  →  Orchestrator reads outbox/A  →  sends to B  →  {session}:agent:{B}:done
```

### Fanout (Parallel Distribution)

Run independent agents concurrently.

```
Orchestrator ──spawn──→ Agent-A ─┐
             ──spawn──→ Agent-B ─┤──all-done──→ Collect
             ──spawn──→ Agent-C ─┘
```

**Best for:**
- Independent domain module development
- Parallel code review + performance analysis
- Independent work across multiple files/directories

### Feedback (Iterative Loop)

Cycle through design → review → revision.

```
Agent-A (design) → Agent-B (review) ──issues?──→ Agent-A (revise) → Agent-B (re-review)
                                       └─ no ──→ Complete
```

**Best for:**
- API design + code review
- Iterating until a quality bar is met
- Max iterations: 2 (default)

### Hybrid (Mixed)

Combine multiple patterns across stages.

```
Fanout Stage → Pipeline Stage → Fanout Stage
```

**Best for:**
- Analysis (parallel) → implementation (sequential) → validation (parallel)
- Most complex project scenarios

### P2P (Peer-to-Peer)

Agents communicate directly without going through the orchestrator.

```
Agent-A ──peer-msg──→ Agent-B ──peer-msg──→ Agent-C
```

**Best for:**
- Fine-grained collaboration within the same layer
- Real-time CRUD + test pipelining
- Autonomous agent coordination

---

## IPC Protocol

### Overview

cmux-agent-teams IPC combines **file-based messages** and **cmux wait-for signals**.

- **Files**: Reliably deliver structured data (JSON). Atomic writes (`mv`) prevent race conditions.
- **Signals**: Deliver event notifications immediately. Blocking wait with no polling needed.

### Communication Modes

| Mode | Path | Description |
|------|------|-------------|
| **orchestrated** | Agent → outbox → Orchestrator → inbox → Agent | Orchestrator mediates (default) |
| **peer-to-peer** | Agent → inbox/OtherAgent/ (direct) | Direct agent-to-agent communication |
| **broadcast** | Agent → inbox/AllAgents/ (copied) | Publish to all agents |

### Atomic Writes

All file writes are performed atomically:

```bash
# 1. Write to a temp file
echo "$content" > "${target}.tmp.$$"
# 2. Atomic move (mv within the same filesystem is atomic)
mv "${target}.tmp.$$" "$target"
```

This prevents readers from ever seeing a partially-written file.

---

## Script Reference

All scripts live in the `skills/cmux-agent-teams/scripts/` directory.

### init-session.sh

Initializes an IPC session. Must be run before all other scripts.

| Item | Details |
|------|---------|
| **Usage** | `init-session.sh [--cwd <path>] [--session <id>]` |
| **Output** | session-id (stdout) |
| **Side effects** | Creates `~/.claude/cmux-agent-ipc/{session-id}/` directory |
| **Exit codes** | 0: success, 1: jq/cmux missing |

| Argument | Default | Description |
|----------|---------|-------------|
| `--cwd` | `$PWD` | Project directory |
| `--session` | auto-generated | Custom session ID |

**Example:**
```bash
SESSION=$(bash init-session.sh --cwd /path/to/project)
export CMUX_AGENT_SESSION=$SESSION
```

---

### spawn-agent.sh

Creates a cmux pane and runs a Claude Code agent inside it.

| Item | Details |
|------|---------|
| **Usage** | `spawn-agent.sh --role <name> --task <desc> [options]` |
| **Output** | agent-id (stdout) |
| **Side effects** | Creates cmux pane, registry/inbox/prompts files, runs Claude Code |
| **Exit codes** | 0: success, 1: argument error/no IPC, 2: pane creation failed |

| Argument | Required | Default | Description |
|----------|----------|---------|-------------|
| `--role` | Yes | - | Agent role (free text) |
| `--task` | Yes | - | Task description |
| `--direction` | No | auto | Manual split direction (right/down/left/up). Auto layout if omitted. |
| `--cwd` | No | `$PWD` | Working directory |
| `--plugin-dir` | No | (none) | Claude Code skill plugin path |
| `--session` | No | `$CMUX_AGENT_SESSION` | Session ID |
| `--peers` | No | (none) | P2P targets (comma-separated) |
| `--agent-id` | No | auto-generated | Custom agent ID |
| `--timeout` | No | `300` | Timeout (seconds) |
| `--model` | No | (none) | Claude model |
| `--sub-agents` | No | off | Allow sub-agent spawning (teammateMode: in-process) |

**Specifying roles:**

```bash
# Use an existing Expert Skill
spawn-agent.sh --role "sub-kopring-engineer" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer \
  --task "Implement UserService"

# Custom role (no skill needed — great for legacy projects)
spawn-agent.sh --role "database-migration" \
  --task "Write Flyway migration scripts" \
  --cwd /path/to/legacy-project

# Specify P2P targets
spawn-agent.sh --role "backend-service" \
  --task "Implement Services" \
  --peers "backend-model-a1b2,backend-controller-c3d4"
```

**Auto grid layout (default):**

When `--direction` is omitted, agents are arranged in a grid of up to 3 per row. The orchestrator is always pinned to the bottom:

```
┌─────────┬─────────┬─────────┐
│ Agent-1 │ Agent-2 │ Agent-3 │  ← row 0
├─────────┼─────────┼─────────┤
│ Agent-4 │ Agent-5 │ Agent-6 │  ← row 1 (new row from 4th agent)
├─────────┴─────────┴─────────┤
│      Orchestrator (bottom)   │  ← orchestrator pinned
└─────────────────────────────┘
```

- First agent: split above (up) the orchestrator
- 2nd–3rd agents in same row: split right of the previous agent
- New row (4th, 7th, 10th...): split down from the first agent of the previous row

---

### send-message.sh

Sends a message to an agent's inbox.

| Item | Details |
|------|---------|
| **Usage** | `send-message.sh --to <id\|broadcast> --type <type> --payload <json>` |
| **Output** | message-id (stdout) |
| **Exit codes** | 0: success, 1: argument error |

| Argument | Required | Description |
|----------|----------|-------------|
| `--to` | Yes | Recipient agent-id or "broadcast" |
| `--type` | Yes | Message type (task/result/peer-request/peer-response/signal/error) |
| `--payload` | Yes | JSON string |
| `--from` | No | Sender (default: "orchestrator") |
| `--signal` | No | Also send a cmux signal after delivering the message |

---

### read-messages.sh

Reads messages from an agent's inbox.

| Item | Details |
|------|---------|
| **Usage** | `read-messages.sh --agent <id> [--consume] [--type <filter>] [--latest]` |
| **Output** | JSON array (stdout) |
| **Exit codes** | 0: always success (may be empty array) |

| Argument | Description |
|----------|-------------|
| `--agent` | Target agent ID |
| `--consume` | Move read messages to .consumed/ |
| `--type` | Filter by specific type |
| `--latest` | Return only the most recent message |

---

### signal-agent.sh

Sends a cmux wait-for signal.

| Item | Details |
|------|---------|
| **Usage** | `signal-agent.sh --name <signal-name>` |
| **Exit codes** | 0: success, 1: failure |

Automatically prepends `{session-id}:` prefix if no session prefix is given.

---

### wait-signal.sh

Waits (blocking) for a cmux wait-for signal.

| Item | Details |
|------|---------|
| **Usage** | `wait-signal.sh --name <signal-name> [--timeout <sec>]` |
| **Exit codes** | 0: signal received, 1: timeout |

| Argument | Default | Description |
|----------|---------|-------------|
| `--name` | (required) | Signal name to wait for |
| `--timeout` | `300` | Timeout in seconds |

---

### check-agent-health.sh

Checks the health status of an agent.

| Item | Details |
|------|---------|
| **Usage** | `check-agent-health.sh --agent <id>` |
| **Output** | JSON `{agent_id, status, surface_id, last_output}` |

**Status values:**
- `running` — currently running
- `completed` — done (result exists in outbox or Claude exit detected)
- `failed` — error pattern detected or result status is failed
- `not_found` — not in registry

---

### list-agents.sh

Lists registered agents.

| Item | Details |
|------|---------|
| **Usage** | `list-agents.sh [--role <filter>] [--status <filter>]` |
| **Output** | JSON array (agent info + has_result, inbox_pending fields) |

---

### monitor-agents.sh

Monitors the status of all agents.

| Item | Details |
|------|---------|
| **Usage** | `monitor-agents.sh [--interval <sec>] [--once]` |
| **Output** | Periodic JSON summary (total, running, completed, failed) |
| **Exits when** | All agents complete |

---

### cleanup-session.sh

Cleans up an IPC session.

| Item | Details |
|------|---------|
| **Usage** | `cleanup-session.sh [--close-panes] [--auto]` |
| **Side effects** | Removes IPC directory, optionally closes agent panes |

| Argument | Description |
|----------|-------------|
| `--close-panes` | Also close agent cmux panes |
| `--auto` | Called from Stop hook (cleans up silently, includes close-panes) |

---

## Message Format Reference

### Common Message Structure

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

### Field Descriptions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string (UUID) | Yes | Unique message ID. Also used as the filename (`{id}.json`) |
| `type` | string | Yes | Message type (see table below) |
| `from` | string | Yes | Sender: `"orchestrator"` or an agent ID |
| `to` | string | Yes | Recipient: agent ID, `"orchestrator"`, or `"broadcast"` |
| `timestamp` | string | Yes | ISO-8601 UTC timestamp |
| `payload` | object | Yes | Message body (structure varies by type) |
| `metadata` | object | No | Additional info (session_id, sequence, reply_to, etc.) |

### Payload Structure by Type

**`task` — Task assignment**

| Payload field | Type | Description |
|--------------|------|-------------|
| `task_description` | string | Task to perform |
| `context.project_root` | string | Project root path |
| `context.dependency_results` | array | Results from previous agents |
| `context.constraints` | string | Constraints |
| `peers` | array | List of agents available for P2P communication |
| `timeout_seconds` | number | Timeout |

**`result` — Result report**

| Payload field | Type | Description |
|--------------|------|-------------|
| `status` | string | `"completed"`, `"partial"`, `"failed"` |
| `result_summary` | string | Summary of work done |
| `artifacts` | array | Absolute paths of files created/modified |
| `metrics` | object | Numeric metrics (file count, elapsed time, etc.) |
| `error` | string\|null | Error message (on failure) |

**`peer-request` / `peer-response` — P2P communication**

| Payload field | Type | Description |
|--------------|------|-------------|
| `task_description` | string | Request/response content |
| `artifacts` | array | Referenced file paths |
| `status` | string | `"pending"` (request), `"completed"` (response) |
| `reply_to` | string | ID of the original peer-request (for responses) |

---

## Signal Naming Convention

All signals start with a `{session-id}:` prefix to prevent collisions across sessions.
Scripts automatically prepend the prefix if you pass just the name.

| Signal Pattern | Sender | Description |
|---------------|--------|-------------|
| `{session}:agent:{id}:ready` | Agent | Initialized and ready to receive tasks |
| `{session}:agent:{id}:done` | Agent | Task complete, result exists in outbox |
| `{session}:agent:{id}:error` | Agent | An error occurred |
| `{session}:agent:{id}:peer-msg` | Sending agent | P2P message delivered to recipient's inbox |
| `{session}:stage:{name}:done` | Orchestrator | Pipeline stage complete |
| `{session}:all-done` | Monitor | All agents have completed |
| `{session}:broadcast:{type}` | Sender | Broadcast message sent |

**Usage examples:**

```bash
# Send a signal (session prefix added automatically)
bash signal-agent.sh --name "agent:backend-a1b2:done"
# → actual signal: "abc123:agent:backend-a1b2:done"

# Wait for a signal
bash wait-signal.sh --name "agent:backend-a1b2:done" --timeout 300
```

---

## Peer-to-Peer Communication

### Overview

P2P communication lets agents talk to each other directly without going through the orchestrator.
It's ideal for fast collaboration between agents in the same domain.

### Setting Up P2P Agents

Use the `--peers` option in `spawn-agent.sh` to designate P2P targets:

```bash
AGENT_A=$(bash spawn-agent.sh --role "backend-model" --task "Entity design" \
  --peers "$AGENT_B_ID")

AGENT_B=$(bash spawn-agent.sh --role "backend-service" --task "Service impl" \
  --peers "$AGENT_A_ID")
```

The specified peer info is included in the system prompt, allowing each agent to write messages directly to the other's inbox and send signals.

### P2P Communication Flow

```
Backend Agent-A (model)                 Backend Agent-B (service)
    │                                       │
    ├── Define Entity (User.kt)            │
    ├── Write intermediate result to outbox │
    ├── peer-request to Agent-B inbox:      │
    │   "User Entity done, please check"    │
    ├── cmux wait-for -S                    │
    │   "...:agent:B:peer-msg" ────────────┤
    │                                       ├── Receive peer-msg signal
    ├── Continue with Order Entity          ├── Read peer-request from inbox
    │                                       ├── Check User.kt in Agent-A outbox
    │                                       ├── Start implementing UserService
    │   ...                                 │   ...
```

### How Agents Discover Each Other

Agents discover peers by reading the registry directory:

```bash
# List all agents
ls ~/.claude/cmux-agent-ipc/${SESSION}/registry/

# Find agents by role
cat ~/.claude/cmux-agent-ipc/${SESSION}/registry/*.json | jq 'select(.role | contains("backend"))'
```

---

## Sub-agents (teammateMode)

### Overview

Sub-agents are an **opt-in feature**. You must add the `--sub-agents` flag to enable them. By default, each agent works on its own.

When enabled, each agent runs with Claude Code's **Agent Teams** feature active, allowing it to split its own work into smaller sub-agents and process them in parallel.

### Usage

**When invoking the skill** (recommended):

```bash
# Default (no sub-agents)
> /cmux-agent-teams pipeline "User domain API: Entity design → Service impl → Controller"

# Add --sub-agents flag → enables sub-agents on all spawned agents
> /cmux-agent-teams pipeline --sub-agents "User domain API: Entity design → Service impl → Controller"

# Works with all patterns
> /cmux-agent-teams fanout --sub-agents "3 independent modules: Auth, Order, Notification"
> /cmux-agent-teams hybrid --sub-agents "Full-stack: APIDesign∥DBDesign → Backend → Frontend"
> /cmux-agent-teams p2p --sub-agents "CRUD API + parallel testing"
```

Passing `--sub-agents` to the skill propagates it internally to `spawn-agent.sh`, applying teammateMode to every agent created.

**When calling scripts manually:**

```bash
# Without sub-agents (default)
spawn-agent.sh --role "backend" --task "Implement API"

# With sub-agents enabled
spawn-agent.sh --role "backend" --task "Implement API" --sub-agents
```

### When to Use It

| Situation | Recommendation |
|-----------|---------------|
| Simple task (generating a few files) | Default (no sub-agents) |
| Complex task (project generation, many files) | Enable `--sub-agents` |
| Token efficiency is a priority | Default |
| Speed is a priority | Enable `--sub-agents` |

This enables **two-level parallelization**:
- **Level 1**: cmux-agent-teams splits work into multiple agents (cmux split pane)
- **Level 2**: Each agent internally spawns smaller sub-agents (in-process)

### How It Works

```
cmux-agent-teams (orchestrator)
│
├── [cmux split] Agent: backend-model
│   └── Claude Code (teammateMode: in-process)
│       ├── Sub-agent: Design User Entity
│       ├── Sub-agent: Design Order Entity
│       └── Sub-agent: Design Payment Entity
│
├── [cmux split] Agent: backend-service
│   └── Claude Code (teammateMode: in-process)
│       ├── Sub-agent: Implement UserService
│       ├── Sub-agent: Implement OrderService
│       └── Sub-agent: Write integration tests
│
└── [cmux split] Agent: frontend
    └── Claude Code (teammateMode: in-process)
        ├── Sub-agent: Generate API client hooks
        ├── Sub-agent: Write page components
        └── Sub-agent: Configure store
```

### Auto-configuration

When creating each agent, `spawn-agent.sh` automatically generates and passes a `settings.json` with:

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

| Setting | Value | Description |
|---------|-------|-------------|
| `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` | `"1"` | Enables Claude Code Agent Teams |
| `teammateMode` | `"in-process"` | Sub-agents run in the same terminal (no extra pane needed) |
| `permissions.allow` | `["Agent", ...]` | Allows key tools including Agent |

### teammateMode Options

| Mode | Behavior | cmux-agent-teams default |
|------|----------|--------------------------|
| `in-process` | Sub-agents run in the same terminal | **Yes (default)** |
| `tmux` | Sub-agents run in tmux/iTerm2 split panes | - |
| `auto` | Automatically chosen based on environment | - |

`in-process` is the default in cmux-agent-teams. Since each agent already runs in its own cmux pane, creating additional panes for sub-agents would overcrowd the screen. `in-process` runs sub-agents quietly within the same pane.

### When Are Sub-agents Useful?

Each agent's system prompt includes a note to "actively use the Agent tool to spawn sub-agents for large tasks." Claude automatically creates sub-agents in situations like:

**When file exploration/analysis is needed:**
- Analyzing the existing codebase while writing new code at the same time
- Inspecting patterns across multiple directories to generate consistent code

**When there are independent sub-tasks:**
- Delegating 3 Entities to separate sub-agents for parallel creation
- Running implementation and testing concurrently

**When complex research is needed:**
- Sub-agent for looking up API docs + main agent for writing code
- Sub-agent for dependency analysis + main agent for writing migration scripts

### Example: Sub-agent Usage by a Backend Agent

When cmux-agent-teams spawns a `backend-model` agent, inside that agent:

```
[Agent: backend-model] running in cmux split pane

Claude: "I need to design 3 Entities. I'll use sub-agents."

  → Sub-agent (Explore): "Analyze Entity patterns in the existing project"
    ← Result: "Using JPA + Kotlin data class pattern"

  → Sub-agent (general-purpose): "Create User Entity"
    ← Result: User.kt created

  → Sub-agent (general-purpose): "Create Order Entity"
    ← Result: Order.kt created

Claude: "All Entities created. Writing results to outbox."
  → Writes result.json to outbox
  → Background monitor detects it → sends signal
  → Orchestrator advances to next pipeline stage
```

This entire process is visible in real-time in the cmux split pane.

---

## External Skill Integration

### Standalone Use (Default)

cmux-agent-teams works fully on its own without any external skills. You can run agents with custom roles in any project.

### Using with Expert Skills

If you have an existing Claude Code skill plugin, connect it with `--plugin-dir`:

```bash
spawn-agent.sh --role "sub-kopring-engineer" \
  --plugin-dir /path/to/plugins/sub-kopring-engineer \
  --task "Implement UserService"
```

In this case the agent uses sub-kopring-engineer's SKILL.md + resources, with the IPC system prompt layered on top.

### Integrating with sub-team-lead

Calling cmux-agent-teams from sub-team-lead's Coordinate phase converts sequential execution to parallel:

```xml
<sister-skill-invoke skill="cmux-agent-teams">
  <caller>sub-team-lead</caller>
  <phase>coordinate</phase>
  <trigger>multi-expert-parallel-via-cmux</trigger>
  <targets>{ "pattern": "pipeline", "agents": [...] }</targets>
</sister-skill-invoke>
```

### Fallback When cmux Is Not Installed

In environments without cmux, the plugin falls back to the traditional sister-skill invoke approach.

---

## Limitations & Troubleshooting

### Limitations

| Item | Limit | Reason |
|------|-------|--------|
| Max concurrent agents | 6 (recommended) | Terminal space + system resources |
| Default timeout | 300 sec (5 min) | Per individual agent |
| Max feedback iterations | 2 | Prevent infinite loops |
| IPC directory | `~/.claude/cmux-agent-ipc/` | Allowed path within Claude Code sandbox |
| cmux required | cmux app must be running | cmux socket communication |

### Troubleshooting

**Q: "cmux is not installed" error**

Make sure the cmux app is installed and running:
```bash
cmux version
cmux ping
```

**Q: Agents not starting**

Check whether cmux panes were created:
```bash
cmux tree
```

Check agent registration info:
```bash
cat ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/registry/*.json | jq .
```

**Q: Signal timeout**

Check whether the agent is actually running via `read-screen`:
```bash
cmux read-screen --surface <surface-id> --lines 20
```

**Q: IPC directory left over**

Manual cleanup:
```bash
bash cleanup-session.sh --session <session-id> --close-panes
# Or clean everything
rm -rf ~/.claude/cmux-agent-ipc/
```

**Q: Agent can't read another agent's result**

Check whether the outbox file exists:
```bash
ls ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/outbox/
```

Verify signals were sent correctly:
```bash
cat ~/.claude/cmux-agent-ipc/${CMUX_AGENT_SESSION}/signals/signal.log
```

---

## License

MIT License. See the [LICENSE](./LICENSE) file.
