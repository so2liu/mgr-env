# Pi 主控 + Claude Code/Codex workers + Herdr 编排：只读调研

检索日期：2026-08-24（Asia/Shanghai）  
任务标记：`PI-HERDR-ORCHESTRATOR-PLUGIN`

## 摘要结论

截至本次检索，没有发现一个可以“一条安装命令即完成 Pi 主控、Claude Code/Codex 两类 worker、并由 Herdr 管理 pane/tab/workspace/worktree/完成通知”的单一 Pi 插件。

最接近的是 **`pi-subagents`（nicobailon）**：它是成熟的 Pi extension/package，提供子 agent、并行/链式 workflow、持久 mission、FleetView、worktree 隔离、完成与阻塞状态，并已经有可选的 Herdr bridge（`HERDR_ENV=1`、`HERDR_PANE_ID`）。它还提供 `external-cli` runner，可把一个 agent profile 的 prompt 通过 stdin 交给任意本地 CLI；但该 runner 不内建 Claude Code/Codex profile，也不支持 Pi tools/skills/structured output/nested subagents 等能力，因此仍需写 profile/薄封装。

如果“worker 必须是真正的 Claude Code/Codex 进程、并且每个 worker 都是 Herdr 可识别 pane/agent”，**直接用 Herdr CLI** 是现成能力最完整的底座；Pi 可以用 extension 的 `pi.exec()`/custom tool 调用 Herdr CLI，或先由外部脚本协调。若主控必须是严格的“只委派、不读写代码”的 Pi，`edxeth/pi-subagents` 的 orchestrator mode 更贴近语义，但它的 worker 仍是 Pi 子进程，不是 Claude Code/Codex。

## 1. 本机 Pi 文档核查

本机 checkout：`/Users/yangliu35/GitHub/pi-mono`，当前 `main`，提交 `5f7195c51`（2026-08-14）。完整核对了 coding-agent 文档中的 `packages.md`、`extensions.md`、`skills.md`、`prompt-templates.md`、`sdk.md`、`rpc.md`、`custom-provider.md`、`security.md`，以及 examples/extensions/subagent 与 examples/sdk 交叉引用。

### Pi 的四种资源不是同一层

| 类型 | 作用 | 是否能直接编排 Herdr/CLI | 关键边界 |
|---|---|---|---|
| **Extension**（TypeScript/JavaScript） | 生命周期事件、LLM custom tool、命令、UI、会话持久化、provider、`pi.exec()` | **可以**。能执行本地 CLI、监听 `agent_end`/`session_shutdown`，并调用 Herdr | 以 Pi 进程用户权限运行；第三方代码等同本地代码；需要自己做状态、ID、错误和幂等 |
| **Skill**（`SKILL.md`，Agent Skills 标准） | 按需加载的流程/操作指导、脚本和参考资料 | **不能单独编排**。Skill 只能指导模型何时调用已有工具/命令 | 可执行脚本和提示均应审查；不是后台 supervisor、不是进程管理器 |
| **Prompt template**（`.md`） | `/template` 展开成一次用户输入/任务模板 | **不能**。适合固定委派话术、验收清单 | 无生命周期、无异步 job 状态、无 pane/worktree API |
| **Pi package**（npm/git） | 分发 extension、skill、prompt、theme 的容器 | **不是新运行时**；只是安装/加载边界 | `pi install npm:...` 或 `git:...`；包/扩展拥有完整系统权限 |

Pi 文档还明确：Pi 默认不提供 sub-agent/plan mode；应由 extension/package 增加。Extension 可注册 custom tool、监听生命周期、写 session entry、做自定义 UI；SDK 适合把 Pi 嵌入宿主程序；RPC（`--mode rpc`）适合外部进程驱动单个 Pi 会话，但本身不是 Claude/Codex orchestration protocol。Pi 没有内置 sandbox，project trust 只控制项目资源加载，不能阻止模型或扩展执行命令。

### 与本需求直接相关的 Pi API

- `pi.registerTool()`：让主控模型调用 `herdr_workspace_create`、`herdr_worker_start`、`herdr_worker_wait` 等窄工具。
- `pi.registerCommand()`：可提供 `/workers`、`/worker-start`、`/worker-status`。
- `pi.exec(command, args, options)`：应使用 argv 数组而非 shell 拼接，便于调用 `herdr`；必须设置超时、取消和输出上限。
- 生命周期：`session_start`、`session_shutdown`、`agent_start`、`agent_end`、`tool_execution_*`、`message_*` 可用于恢复/清理/通知。
- `pi.appendEntry()`：可保存 worker/job 映射，避免只靠 TUI 输出解析。
- RPC/SDK：可把 Pi 当作 headless supervisor，但仍须由宿主或 extension 负责 Herdr ID 与 worker 结果关联。

## 2. Herdr 当前可提供的能力（本机 `herdr 0.8.2` 实测帮助输出）

Herdr 官方仓库：[herdrdev/herdr](https://github.com/herdrdev/herdr)（Apache-2.0；GitHub API 于 2026-08-24 显示约 31.9k stars、2.3k forks、当天仍有提交）。官方定位是 coding-agent runtime/terminal workspace manager。

### 可用 CLI 面

- **workspace**：`list/create/get/focus/rename/report-metadata/close`。
- **tab**：`list/create/get/focus/rename/close`。
- **pane**：`list/current/get/layout/process-info/resize/zoom/split/move/close/send-text/send-keys/wait-output/run`，以及 `report-agent`、`report-agent-session`、`report-metadata`、`release-agent`。
- **worktree**：`list/create/open/remove`，可按 workspace/cwd、branch/base/path 管理。
- **agent**：`list/get/read/send-keys/prompt/wait/rename/focus/attach/start/explain`。安装版列出的 kind 包含 `pi`、`claude`、`codex` 等；`agent prompt ... --wait` 可等待 `idle/done/blocked`。
- **notification**：`herdr notification show <title> [--body ...] [--sound none|done|request]`。
- **integration**：可安装/卸载/查看 `pi`、`claude`、`codex` 等集成。
- **api**：`snapshot`、`schema`；大多数控制命令返回 JSON，应读取返回的 opaque ID，不应猜测 `w1/p1`。

因此 Herdr 已覆盖用户要求的 pane/tab/workspace/worktree、agent 状态、等待、完成/请求通知。缺口不在“能否启动 cc/codex”，而在“Pi 如何成为有持久 job、结果回传、重试/取消/权限策略的 supervisor”。

## 3. 候选方案（按推荐度排序）

### 1）`pi-subagents`（nicobailon）——推荐组合底座

- 仓库：[github.com/nicobailon/pi-subagents](https://github.com/nicobailon/pi-subagents)
- npm：[pi-subagents](https://www.npmjs.com/package/pi-subagents)
- 当前核验：npm `0.56.0`，MIT；GitHub 约 3,266 stars/551 forks，2026-08-24 仍有提交，维护非常活跃。
- 安装：`pi install npm:pi-subagents`。
- 已覆盖：Pi parent/child sessions、builtin scout/researcher/worker/reviewer/oracle/delegate、并行/链式 workflow、background runs、FleetView、mission/持久记录、worktree isolation、RPC/event-bus extension API、恢复/steer/stop/resume、完成与 blocked 状态。
- **Herdr**：官方 extension-api 文档说明，Herdr 环境变量存在时自动向当前 pane 报 active-run metadata；可用 `inspector.open/status/close`，Herdr 0.7.5+ 可用 `project.open/status/close` 打开项目级 Pi peer pane；Pi session 是自己的 metadata publisher。
- **外部 CLI**：profile 支持 `runner.type: external-cli`，通过 argv 启动本地命令、stdin 交付合并 prompt，支持 async/status/log/timeout/stop；明确不支持 foreground/clarify、steer/resume、Pi tools/extensions、skills、structured output、nested subagents、fallback models。
- **缺失**：没有现成、经过该项目声明的 `claude` 与 `codex` 外部 profile；Herdr bridge 主要是 Pi async-run metadata/project pane，不等于自动为每个外部 CLI 创建并拥有 Herdr agent pane。需要自己定义 runner 或利用 Herdr CLI。
- **风险**：包是任意 TypeScript，且 worker 可写工作树；external CLI 会继承本地凭据/环境，prompt/stdout/stderr 可能泄漏源码、路径、环境变量。应 pin npm/git ref、审查源码、限制 cwd/tools、对 Herdr IDs 做 ownership 校验。

结论：最适合“先安装、再组合”。先用它作为 Pi 的 workflow/job/result 层；cc/codex worker 由 Herdr agent API 或一个窄 external runner 启动。

### 2）`edxeth/pi-subagents`——最贴近“Pi 纯 orchestrator + Herdr 可见 worker”

- 仓库：[github.com/edxeth/pi-subagents](https://github.com/edxeth/pi-subagents)
- 当前核验：`2.7.4`，MIT；约 113 stars/22 forks，2026-08-20 有提交，活跃但规模明显小于 nicobailon 版本。
- 安装：`pi install git:github.com/edxeth/pi-subagents`。
- 强项：明确的 `PI_ORCHESTRATOR_MODE=1`；移除主控的 read/bash/edit/write/grep/find 等工具，只保留 delegation，系统提示改成分解、委派、综合；interactive children 可通过 Herdr/cmux/tmux/zellij/WezTerm 创建可见 surface，background children headless；有 async/sync、named agents、resume、实时 TUI、完成通知。
- 缺失：子 agent 是 Pi 进程，不是 Claude Code/Codex CLI；没有现成的 Herdr-native cc/codex bridge；依赖和 API 版本漂移风险较高。
- 风险：`PI_ORCHESTRATOR_MODE` 是环境变量（会影响启动行为）；交互 mux、子进程和凭据边界要单独审查；README 的“Claude Code 同类 COORDINATOR_MODE”是项目说明，不是 Anthropic 官方兼容保证。

结论：如果用户优先级是严格委派型主控，选它；若 worker 必须是 cc/codex，则只能作为参考或二次改造，不建议直接安装后宣称满足需求。

### 3）`@jmcombs/pi-relay` + 一个 subagent extension——最接近“Pi worker 调 Claude Code”

- 仓库：[github.com/jmcombs/pi-extensions/tree/main/packages/relay](https://github.com/jmcombs/pi-extensions/tree/main/packages/relay)
- npm：[@jmcombs/pi-relay](https://www.npmjs.com/package/@jmcombs/pi-relay)
- 当前核验：`1.1.3`，MIT；仓库约 5 stars，2026-08-23 有提交，小而活跃。
- 安装：`pi install npm:@jmcombs/pi-relay`。
- 已覆盖：注册 `relay-claude` provider，把 Pi subagent 的 model 设为 `relay-claude/opus` 后调用 headless `claude -p`；工具映射、skill 内容内联、read-only allowlist、wall cap、heartbeat、cut-run 输出 `UNVERIFIED`。另有 `relay-grok`。
- Codex 状态：仓库的 `drivers/codex.ts` 是 documented seam-only stub，**不是可用 Codex backend**。
- Herdr 状态：README 未提供 Herdr 编排桥；relay 是 provider/driver，不是 workspace/pane/worktree manager。
- 风险：外部 CLI 权限映射若配置错误会扩大写权限；`claude -p` 继承订阅认证和本机环境；结果只是一轮文本，不能期待 Pi 的 nested subagent/tool semantics。

结论：适合“Pi 子 agent → headless Claude Code verifier”，不适合作为完整 Herdr fleet 控制面；可与 `pi-subagents` 组合，但 Codex 仍需另写 driver。

### 4）`HazAT/pi-interactive-subagents`——早期、直观的 pane 方案

- 仓库：[github.com/HazAT/pi-interactive-subagents](https://github.com/HazAT/pi-interactive-subagents)
- 当前核验：`3.7.2`，MIT；约 623 stars/123 forks，2026-05-12 最近提交，维护速度低于前述方案。
- 安装：`pi install git:github.com/HazAT/pi-interactive-subagents`。
- 覆盖：非阻塞 Pi 子 agent、独立 mux pane、状态 widget、resume；支持 cmux/tmux/zellij/WezTerm。
- 缺失：没有原生 Herdr 语义（README 的支持列表不含 Herdr）、worker 仍是 Pi、没有 Claude/Codex runner。

结论：可作为最小 pane UX 参考，不建议作为当前主方案。

### 5）`pi-subagent-workflow`（mzenko）——脚本化、可恢复的 Pi workflow

- 仓库：[github.com/mzenko/pi-subagent-workflow](https://github.com/mzenko/pi-subagent-workflow)
- npm：[pi-subagent-workflow](https://www.npmjs.com/package/pi-subagent-workflow)
- 当前核验：`0.5.1`，MIT；约 1 star，2026-08-06 有提交，早期项目。
- 安装：`pi install npm:pi-subagent-workflow` 或 `pi install git:github.com/mzenko/pi-subagent-workflow`。
- 覆盖：每次调用一个隔离 Pi 子进程，workflow JS 的 phase/parallel/pipeline、journal/resume、可选 worktree patch、`/agents` overlay。
- 缺失：没有 Herdr 集成、没有 cc/codex worker、没有 pane/tab/workspace 管理。

结论：适合研究确定性 workflow API，不适合作为需求的运行时底座。

### 6）Herdr 原生 CLI + `herdr-claude-manager`——真实 cc/codex fleet 的直接底座

- Herdr：[github.com/herdrdev/herdr](https://github.com/herdrdev/herdr)，Apache-2.0，极活跃。
- 辅助脚本：[github.com/richardadonnell/herdr-claude-manager](https://github.com/richardadonnell/herdr-claude-manager)，MIT；约 1 star，2026-08-11 有提交。
- `herdr-claude-manager` 只做 N 个 Claude pane 的 workspace 菜单、列出/恢复/杀掉 workspace；不是 Pi 插件，也不支持 Codex orchestration。
- Herdr 本身已支持 `agent start --kind claude|codex`、prompt/wait、worktree create/open/remove、pane/tab/workspace JSON API 和 notification，因此对“worker 真的是 cc/codex、可见于 Herdr”最可靠。

结论：若接受薄 Pi extension 或外部脚本，这是最稳的组合；不要把 `herdr-claude-manager` 误称为 Pi extension。

### 7）通用 agent orchestrator：CAO / AoE / Codex Orchestrator（不属于 Pi extension）

| 项目 | 链接/状态 | 覆盖 | 与目标的缺口 |
|---|---|---|---|
| AWS CLI Agent Orchestrator | [awslabs/cli-agent-orchestrator](https://github.com/awslabs/cli-agent-orchestrator)，Apache-2.0，约 1,118 stars，2026-08-24 活跃；`uv tool install ...` | supervisor、并行/序列、Claude/Codex 等 CLI、tmux、Web UI、MCP/plugins、skills/workflows | 主控是 CAO/Kiro/其控制面，不是 Pi；不使用 Herdr pane API |
| Agent of Empires | [agent-of-empires/agent-of-empires](https://github.com/agent-of-empires/agent-of-empires)，MIT，约 3,127 stars，2026-08-24 活跃；`brew install aoe`/脚本 | Claude、Codex、Pi 等多 CLI、tmux、worktree、状态、Web dashboard、通知、Docker sandbox | 自己就是 session manager；不能作为 Pi extension 直接嵌入，也不以 Herdr 为底座 |
| Codex Orchestrator | [kingbootoshi/codex-orchestrator](https://github.com/kingbootoshi/codex-orchestrator)，MIT，约 348 stars，2026-05-28；Claude Code plugin + `codex-agent` CLI | Claude 主控调 Codex tmux jobs、status/send/capture/watch、完成 shell notification、sandbox 参数 | 不是 Pi package；依赖 Claude Code plugin、tmux/Bun；无 Herdr |

这些项目是“通用 agent orchestrator / CLI 工具 / MCP 控制面”，不能与 Pi extension、skill、prompt template 混为一谈。它们可作为架构参考或独立替代方案，但不应直接安装进 Pi 期望自动工作。

## 4. 推荐决策

1. **推荐直接安装并组合**：`pi-subagents` + Herdr 0.8.2。Pi 负责任务拆解、workflow、mission、结果收敛和恢复；Herdr 负责真实 `claude`/`codex` 进程、pane/tab/workspace/worktree、状态和 notification。先只启用 read-only worker 验证链路，再开放写入。
2. **若必须“主控不能执行任何代码”**：评估 `edxeth/pi-subagents` orchestrator mode；但将 cc/codex worker 交给 Herdr 外部启动，不能依赖其内置 Pi child。
3. **若主要需求是 Claude Code verifier**：`pi-subagents` + `@jmcombs/pi-relay`；明确 Codex driver 仍未实现，Herdr 只需由另一个薄层提供可视化/通知。
4. **不建议直接安装** CAO/AoE/Codex Orchestrator 到 Pi；它们是替代控制面，不是 Pi 扩展。只有当用户愿意放弃 Pi 主控或接受双控制面时才考虑。

## 5. 是否值得自建薄 Pi extension

**值得，但应是“Herdr CLI adapter”，不是第二套 agent runtime。** 现成项目已经解决了大量 Pi 子 agent 生命周期；自建层只需把 Herdr 的 opaque IDs、真实 CLI agent 状态和 Pi job 关联起来。

### 最小边界

- 只支持 `claude`、`codex` 两种 kind；不在 extension 内实现模型调用、prompt 编排、worktree diff 合并或 TUI mux。
- 所有写操作显式使用 `cwd`/workspace ID，默认 `--no-focus`；不根据 sidebar 顺序猜 ID。
- 只保存 `{jobId, workspaceId, tabId, paneId, agentName, kind, worktreePath, status}`，用 `pi.appendEntry()` 持久化；启动时从 Herdr/entry 恢复并校验 ownership。
- `start`：workspace/worktree（可选）→ tab/pane → `herdr agent start <name> --kind <kind> --pane <id>`。
- `prompt`：`herdr agent prompt <name> <text> --wait --timeout ...`；返回 JSON，识别 `idle/done/blocked/unknown`。
- `status`：`herdr agent get/read/explain` + `herdr pane get`，只返回必要字段。
- `wait`：`herdr agent wait ... --until done|blocked|idle`；超时不宣称完成。
- `stop`：先确认 ownership，再 `pane close` 或 agent 终止；默认需要用户确认。
- `notify`：完成/blocked/error 调 `herdr notification show`，并向 Pi 发 `sendMessage`/steer 消息。
- `cleanup`：`session_shutdown` 时释放 metadata；不关闭用户未创建的 workspace/pane。

### API/命令草图（不实现）

```ts
pi.registerTool({
  name: "herdr_worker",
  parameters: {
    action: "start | prompt | status | wait | stop | notify",
    jobId?: string,
    kind?: "claude" | "codex",
    task?: string,
    cwd?: string,
    worktree?: { branch?: string; base?: string },
    timeoutMs?: number,
  },
  execute: async (_id, input, signal, _update, ctx) => {
    // validate paths/IDs; invoke `herdr` with argv; parse JSON; persist mapping
  },
});
```

可选命令：`/herdr-workers`（列表）、`/herdr-worker <kind> <task>`（启动）、`/herdr-wait <jobId>`、`/herdr-stop <jobId>`。若已有 `pi-subagents`，更优先使用其公开 extension RPC（`subagents:rpc:v1:request` 的 `spawn/status/steer/stop/resume`），把 Herdr adapter 作为外部 runner/observer，而非复制 FleetView、mission、acceptance 和 workflow。

### 安全要求

- 不把 `HERDR_CONFIG_PATH`、API keys、完整环境变量或 pane 原始输出写入报告/日志；对 prompt、stdout、stderr 做长度上限和敏感字段过滤。
- npm/git 安装固定版本或 commit，先审查源码；Pi 文档警告第三方 package/extension/skill 均可能执行任意代码。
- Herdr CLI 使用 opaque ID 和 ownership/agent-session 校验；不接受用户 prompt 里的任意 shell 字符串，不调用 `sh -c`。
- worker 默认 read-only；写入必须显式选择 worktree/sandbox，并在完成通知中区分 `done`、`blocked`、`unknown`、`timed out`、`UNVERIFIED`。
- 不把“收到 idle”当作“任务成功”；必须结合 agent 输出、退出/完成证据和可选验收命令。

## 来源与检索记录

### 本机文档（本地证据）

- [Pi packages 文档（本机 checkout）](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/packages.md)
- [Pi extensions 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/extensions.md)
- [Pi skills 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/skills.md)
- [Pi prompt templates 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/prompt-templates.md)
- [Pi SDK 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/sdk.md)
- [Pi RPC 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/rpc.md)
- [Pi custom provider 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/custom-provider.md)
- [Pi security 文档](https://github.com/earendil-works/pi-mono/blob/main/packages/coding-agent/docs/security.md)
- [Pi subagent extension example](https://github.com/earendil-works/pi-mono/tree/main/packages/coding-agent/examples/extensions/subagent)

### 官方/原仓库与 npm

- [Pi 官方仓库](https://github.com/earendil-works/pi-mono)；[Pi package gallery](https://pi.dev/packages)
- [pi-subagents（nicobailon）](https://github.com/nicobailon/pi-subagents)；[npm](https://www.npmjs.com/package/pi-subagents)
- [pi-subagents（edxeth）](https://github.com/edxeth/pi-subagents)
- [pi-interactive-subagents](https://github.com/HazAT/pi-interactive-subagents)
- [@jmcombs/pi-relay](https://github.com/jmcombs/pi-extensions/tree/main/packages/relay)；[npm](https://www.npmjs.com/package/@jmcombs/pi-relay)
- [pi-subagent-workflow](https://github.com/mzenko/pi-subagent-workflow)；[npm](https://www.npmjs.com/package/pi-subagent-workflow)
- [Herdr 官方仓库](https://github.com/herdrdev/herdr)；[官网](https://herdr.dev)
- [Herdr + Claude manager](https://github.com/richardadonnell/herdr-claude-manager)
- [AWS CLI Agent Orchestrator](https://github.com/awslabs/cli-agent-orchestrator)
- [Agent of Empires](https://github.com/agent-of-empires/agent-of-empires)
- [Codex Orchestrator](https://github.com/kingbootoshi/codex-orchestrator)

检索方法：本机 Pi 文档/示例与 `herdr --help`、`herdr --skill`、`herdr --version`；GitHub 原仓库 README/package.json/API metadata；npm `npm view/search`。未使用聚合文章；GitHub stars、最近提交和 npm 版本均为检索日快照，后续可能变化。
