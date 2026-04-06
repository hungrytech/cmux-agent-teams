# LinkedIn Post — cmux-agent-teams 소개

---

**Claude Code의 Agent Teams, 제대로 쓰고 계신가요?**

Claude Code에는 이미 강력한 기능이 내장되어 있습니다.
Agent Teams — 에이전트가 스스로 서브에이전트를 스폰해서 병렬로 작업을 나누는 기능입니다.

그런데 실제로 써보면, 한 가지 아쉬운 점이 있습니다.

"서브에이전트가 뭘 하고 있는지 보이지 않는다."

메인 에이전트 하나의 터미널 안에서 모든 게 조용히 돌아갑니다. 서브에이전트가 어떤 파일을 만들고 있는지, 지금 어디까지 진행됐는지, 혹시 막혀 있는 건 아닌지 — 알 수가 없습니다.

그래서 cmux를 활용했습니다.

cmux는 Claude Code 전용 터미널 멀티플렉서입니다. 핵심은 이 세 가지입니다:

- `new-split` — 터미널을 자유롭게 분할
- `wait-for` / `wait-for -S` — 프로세스 간 시그널 동기화
- `respawn-pane` — 특정 pane에 명령을 직접 실행

이 세 가지만으로 "에이전트마다 독립된 터미널 pane을 할당하고, 시그널로 동기화하는" 구조를 만들 수 있었습니다.

**cmux-agent-teams**는 이 위에 올린 오케스트레이션 레이어입니다.

```
/cmux-agent-teams pipeline "Entity 설계 → Service 구현 → Controller 작성"
```

이 한 줄이면 에이전트 3개가 분할 창에 나란히 뜨고, 각자 맡은 작업을 실시간으로 수행합니다.

기존 Agent Teams와 가장 큰 차이는 **가시성**입니다.

각 에이전트가 독립된 cmux pane에서 돌아가기 때문에, 옆에서 동료가 코딩하는 걸 지켜보듯이 모든 과정이 눈에 보입니다. 어떤 파일을 만들고, 어디서 고민하고, 언제 끝나는지 — 블랙박스가 아닙니다.

```
┌─────────┬─────────┬─────────┐
│ Agent-1 │ Agent-2 │ Agent-3 │
├─────────┼─────────┼─────────┤
│ Agent-4 │ Agent-5 │ Agent-6 │
├─────────┴─────────┴─────────┤
│      Orchestrator (하단)     │
└─────────────────────────────┘
```

에이전트가 늘어나면 행당 3개씩 자동 그리드 배치되고, 오케스트레이터는 항상 하단에 고정됩니다.

그리고 여기에 `--sub-agents` 옵션을 더하면, Claude Code의 Agent Teams 기능까지 함께 켜집니다.

```
/cmux-agent-teams pipeline --sub-agents "Entity 설계 → Service 구현 → Controller 작성"
```

cmux pane 위에서 돌아가는 각 에이전트가, 내부적으로 또 서브에이전트를 스폰합니다. **팀 안에 팀**이 생기는 2단계 병렬화입니다. cmux가 제공하는 가시성 위에, Claude Code Agent Teams의 확장성을 얹은 구조입니다.

에이전트 간 통신도 됩니다. 파일 기반 IPC와 cmux 시그널로 결과를 넘기고, P2P로 실시간 협업도 가능합니다. 백엔드끼리, 프론트끼리, 풀스택 파이프라인 — 어떤 조합이든 됩니다.

이 프로젝트를 만들면서 느낀 건, Claude Code에는 이미 좋은 도구들이 있다는 것입니다. Agent Teams도, cmux도. 다만 이 둘을 조합하면 각각 따로 쓸 때와는 차원이 다른 경험이 됩니다.

에이전트를 '보이지 않는 곳에서 혼자 돌리는 것'이 아니라, '눈앞에서 팀으로 협업시키는 것'. 그게 이 프로젝트가 제안하는 방식입니다.

오픈소스로 공개했습니다. 관심 있으신 분은 한번 써보시고 피드백 주세요.

GitHub: https://github.com/hungrytech/cmux-agent-teams

#ClaudeCode #AgentTeams #cmux #MultiAgent #AI #OpenSource #DeveloperTools
