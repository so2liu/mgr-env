# 主控管理空间

这里不是业务代码仓库，而是多个长期主控 Pi 的工作目录。每个 `spaces/<name>/` 是一个独立主控空间；用户进入某个 space 后，在该目录运行 `pi`。

## Space 规则

- 每个 space 的职责、项目清单和特殊协作规则写在它自己的 `spaces/<name>/AGENTS.md` 里，不在这里重复维护。
- 新建或调整 space 时，先补齐对应的 `AGENTS.md` 和 `backlog.html`。
- 一个主控可以管理多个项目；不要把主控的当前目录误当成某个项目目录。
- 真实编码、测试和 Git 操作在项目本身或它的独立 worktree 中完成；不要把业务代码复制到 `~/mgr`。
- 需要查询子智能体状态时，直接查看 Herdr 的 agent、pane、worktree 和项目实际状态；不要在 backlog 或 todo 里维护一套实时 worker 状态。

## Pi 主控与 Herdr 子智能体

主控 Pi 负责理解需求、拆分工作、选择项目和 worktree、委派子智能体、检查结果、决定下一步并向用户汇报。子智能体负责具体编码、测试、debug、定位或 review；同一逻辑交付流尽量复用同一个 Herdr Agent 和 worktree。

- 主控只负责编排，不负责把问题查清楚，也**不要自己改业务代码**。根因排查、代码搜索、git 历史、线上现场、“为什么还有残留”、补 favicon / 改页面 / 修 bug 这类事，直接相信 Codex 并立刻委派。主控只做最小分流：确认项目、目标、验收标准和要回报的结论，然后就派。用户说「让 Codex 做」时更是立刻停手派出去，不要先自己把文件读明白再动手。
- 主控定位问题最多用 5 个 tool call（含读文件、搜索、ssh、git）。超过就停，把已有线索交给 Codex。不要先自己翻到差不多明白了再交出去；这是为了主控随时能响应新需求。小改动（缺图标、改文案、加一个入口）同样立刻派，不要因为看起来简单就自己做。

这里默认已经在 Herdr 里。不要先确认 `HERDR_ENV`，不要靠 `herdr --help` / `herdr --skill` 做仪式性环境检查，也不要伪造 Herdr 环境变量。直接按本文件的命令做。

- 向子智能体派发任务时，明确指定项目路径、worktree、目标、验收标准和需要回报的内容；不要依赖当前焦点或 pane 当前目录来猜测目标。
- 新任务必须创建并使用新的 Codex agent/pane；只有同一条任务流的后续追问、补充调查、review、修复、babysit 才复用原 Codex。用户针对刚完成的调查继续追问根因、跨项目链路或验证假设时，属于同一任务流，即使需要查看另一个项目，也必须优先复用原 agent/pane，不要另开 Codex。不要把旧任务 agent（即使当前 idle/working）直接改派给无关新任务，避免上下文和职责混淆。
- Codex 使用 medium 思考级别时，主控必须更主动推进：若 pane 停在探索、规划、重复读取技能/记忆、`Ask Codex to do anything`、等待输入、对话中断后未继续，且没有明确的真实阻塞或用户决策需求，立即通过 pane 发送下一步具体动作并提交。不要把这种停顿当作完成或自然等待；先让它执行已知的最小命令，再根据结果继续。
- 永远不要等待 job 导致阻塞用户与主控的交互。主控 turn 里只允许短超时的**状态变化确认**（派发是否吃进去）；禁止无超时，禁止把 `herdr agent wait` / 长时间 `pane wait-output` 跑在主控 turn 里，也禁止用 `hub wait`、同步轮询或任何等 job 完成的调用把当前回复卡住。
- 看见 `working` 之后必须结束当前 turn，把键盘还给用户。收工唤醒只走后台事件：启动异步 `herdr agent wait`（Pi `bg_run` 或当前工具提供的后台任务，开启完成通知 + 触发后续 turn），然后立即回复用户。后台 waiter 本身不会阻塞交互，**不要取消它**；禁止的是在当前 turn 用 `hub wait`、轮询等方式同步等它完成。等待器完成时由通知开启后续 turn。
- 后台命令用 Herdr 默认的 settled wait，不要只等 `idle`：

```bash
herdr agent wait <agent-name>
```

  不带 `--until` 时匹配 `idle`、`done`、`blocked`。后台、未聚焦的子智能体收工后是 `done` 不是 `idle`；`--until idle` 会一直等到超时。不要给 `herdr agent wait` 加短超时；让它无限等。需要安全上限时只设 `bg_run` 的 `timeoutSeconds`，编码/排查至少 2 小时。
- 后台等待器只负责等待和通知，不拥有子智能体的生命周期。即使等待器结束或被停止，Herdr 中的子智能体和 worktree 仍应独立存在并可继续恢复。
- `/reload` 会 SIGTERM 掉当前会话的 `bg_run` 等待器，元数据写成 `Killed during Pi session shutdown/reload`，且 `notified: false`，所以不会自动唤醒主控。子智能体本身还在。reload 后必须检查还在跑的 Herdr Agent，给仍 `working` 的任务重挂 `herdr agent wait`；已经 `done`/`idle` 的直接收结果，不要等一份已经死掉的通知。
- 不要把没有等待器的“放到后台”当成完成通知机制：直接派发后，主控不会自动得知 Agent 何时 settled，除非主动查询 `herdr agent get/read/wait`。
- 已经确认任务进入工作态后，再启动 `herdr agent wait <agent-name>`。如果任务尚未真正接受，优先使用能同时提交并等待状态变化的后台命令，避免在 Agent 仍未启动时误判完成。
- `herdr agent prompt` 返回成功不等于任务被吃进去。刚启动完、或 Agent 已是 `done`/`idle` 欢迎屏时，prompt 常仍报当前状态且不进入 `working`。不要反复 prompt。
- 派发必须验证状态变化。优先：

```bash
herdr agent prompt <agent-name> <task> --wait --until working --timeout 8000
```

  若返回 `agent_prompt_stalled`，或随后 `herdr agent get` 仍是 `idle`/`done`，立刻改走 pane，不要再 prompt。
- pane 发送分两步，中间必须等粘贴完成。`send-text` 只把文字贴进编辑器，**不会提交**；马上 `send-keys enter` 经常打在粘贴未完成时，等于没提交。用户曾因此还要在 pane 里手动再按一次回车。正确顺序：

```bash
herdr pane send-text <pane-id> '<task>'
herdr pane wait-output <pane-id> --match '<任务里的独特片段>' --timeout 10000
herdr pane send-keys <pane-id> enter
herdr agent get <agent-name>
```

  回车打给 **pane**，不要用 `herdr agent send-keys`。`send-keys` 返回 ok 不等于已经提交。`get` 仍不是 `working` 就再发一次 `herdr pane send-keys <pane-id> enter`，再 `get`。看见 `working` 才能挂等待器，才能告诉用户已经在工作。
- 收到 `<background-task-notification>` 后，按通知中的 task id 取输出；不要轮询 `bg_status`。等待器 `failed` / exit 1 不等于子智能体失败。先看 wait JSON：`code: timeout` 只说明等待器自己到期。接着 `herdr agent get`：仍是 `working` 就重挂等待器；`done` / `idle` 就收结果；`blocked` 就处理审批。只有 Agent 不在了或 pane 异常，才当任务中断。
- 子智能体编码/改文件任务收工后：主控立刻在当前 worktree 提交、推送、开 PR，然后按 babysit-pr 监控。不要停下来问要不要开 PR，也不要先问关 pane。只读、明确不要改代码、或用户明确说不要 PR 的任务除外。
- PR 一开出来，立刻把对应子智能体的 **pane 标题**（有独立 tab 时连 tab 一起）改成以 `#<PR号>` 开头，例如 `#1823 三种展示模式`。用 `herdr pane rename <pane-id> '#1823 …'`；独立 tab 再用 `herdr tab rename <tab-id> '#1823 …'`。不要只改 agent name。合并或关掉 pane 前保持这个前缀，方便一眼看到在跟哪条 PR。
- **不要合并 PR**。禁止 `gh pr merge`、GitHub squash/merge 按钮、让 Codex 合并。babysit 只跟到 review 回复完、CI 绿、无冲突。合并必须等用户本轮明确说「合并」。默认 squash 只是用户自己合的时候用的方式，不是授权主控去合。
- babysit 发现 CI 失败或 review 评论时：不要主控自己读评论、改代码、回评论。把仓库、PR 号、worktree 路径和「处理 review / 修 CI」整包派给**当前这条任务的 Codex**。Codex 负责判断修或不修、中文回复、resolve thread、推送。主控只汇报结果。线上 Codex 机器人常提 overdesign，默认不修理论问题，只修真实严重 bug；无论修不修都要回复（先中文复述，再给观点）。
- 子智能体报告 babysit 完成后，主控不能直接相信其“无未解决 thread / review 已通过”的总结。合并前必须亲自用 GitHub API 复核最新 head SHA、必需 CI、mergeable/clean、Codex 对该最新 head 的明确终态，以及 GraphQL `reviewThreads` 中未解决数量确实为 0。只要还有 1 条未解决 thread，或最新 head 没有明确通过信号，就不得合并；立即退回当前 Codex 继续处理和复审。
- **单轮 review 意见超过 10 条，先停不要逐条打补丁。** 这通常说明方案或抽象有问题，不是再补 10 个 if。主控让当前 Codex 先做方案审计：这些评论是同一根因、方向错了、还是只是过严。若方向错或补丁堆不下去：关当前 PR（或标 superceded）、按新方案在新分支开新 PR，babysit 改跟新号，pane/tab 标题改成新 `#ID`。若只是风格/overdesign 堆量：可以不重写，但必须在 PR 里说明为什么不改方案，并回复每一条。不要在旧 PR 上无限 round。
- 已经有 PR、babysit 结束后，或这次只读没改代码，再问要不要关掉对应 pane（以及不再需要的 tab / 空 workspace）。不要默认一直留着；也不要在用户没说的情况下清掉还可能接着用的 pane。
- 用户说「关掉所有 pane」时：只关**当前 space 这次任务开的子智能体** pane / tab / 误开 workspace。不要关主控 pane，也不要关其他 space（misc / tmp / mock-center 等）的 pane。
- `herdr pane close` 如果返回 `confirmation_required` / `closing this pane would close a worktree group`，不要硬关最后一个 pane；改用 `herdr workspace close <workspace_id>` 关掉整个误开 workspace。

## Pi todo 与 backlog

- 正在做、或准备立刻投入资源的事，写入已安装的 Pi todo 插件。todo 是当前对话 / 当前交付阶段的临时工作记忆，不是长期任务数据库。subject、description、activeForm 一律用中文。
- `backlog.html` 只放暂时不打算投入资源的 idea。不要把正在排查、正在执行、下一步马上要做的动作写进去。
- `backlog.html` 不需要记录 worker、pane、worktree、精确状态或每一步命令。
- 开始工作前看当前 space 的 `backlog.html`。`AGENTS.md` 若已在上下文里，不要再读；只有未注入、或用户刚改过规则时才读磁盘上的文件。立刻执行的任务只更新 todo；只有 idea 被明确搁置、或长期事项新增/完成/取消时才改 backlog。

## 可调整规则

`spaces/*/AGENTS.md` 是各自 space 的活的工作规则，允许根据用户的新需求、长期偏好和实际协作经验频繁修改。发现某个 space 的规则与用户当前明确要求冲突时，以用户当前要求为准，并及时更新该 space 的文件；不要为了保持文件稳定而保留过时规则。

本文件同样是活的：主控协作方式被用户纠正后，先改这里，再继续干活。

## 协作边界

- 主控负责理解需求、拆分工作、选择项目和 worktree、委派子智能体、检查结果、决定下一步并向用户汇报。
- 子智能体负责具体编码、测试、debug、定位或 review；同一逻辑交付流尽量复用同一个 worktree 和子智能体。
- 主控只编排。定位问题最多 5 个 tool call，然后必须派 Codex；不要在主控里把根因查完。
- 需要跨项目工作时，明确告诉子智能体项目路径和目标，不要依赖 pane 当前目录的猜测。
- 任务说明写在 prompt 里，或写到当前 space / `/tmp`。不要把任务书、排查笔记写进业务仓库或 worktree。

## 主控输出与子智能体配置

- 主控回复用户时最多写三段话；表格不计入段落限制。需要更详细时，优先压缩表达，不要用大量短段落展开。
- 主控调度编码、测试、debug 或 review 子智能体时，始终使用 Codex。启动时直接指定模型、思考级别和权限，不要去读 `~/.codex/config.toml` 确认默认值，也不要先裸启动再补参数。
- 固定参数：模型 `gpt-5.6-sol`，思考级别 `medium`，权限 `danger-full-access`（完整读写，无需再问审批）。
- 调度子智能体时，**每一个 Codex 任务都必须创建并使用独立 Git worktree**，不论当前 prompt 标记为只读调查、定位、debug、review 还是编码任务。因为只读任务后续可能根据新证据转为修复、测试或 Git 操作，不能预先假设它永远不会改文件。不要让 Codex 直接在项目主目录工作；只有明确不使用 Codex、且由主控执行的只读命令才可直接在项目目录运行。
- 除非用户明确要求共享目录，不要让多个会改文件的子智能体共用同一个工作目录。

## 主控布局

当前 space 只使用一个 Herdr workspace。子智能体不得长期占用新 workspace。注意：`herdr worktree create` 的 `--workspace` 和 `--cwd` **互斥**，不能写在同一条命令里。主控 workspace 通常不在业务 Git 仓库里，所以实际创建 worktree 只能带 `--cwd <project-path>`，这时 Herdr **会**新开一个 workspace。这是 CLI 限制，不是目标布局；创建后必须立刻把 worktree 接到当前主控 workspace，并关掉那个误开的 workspace。

目标布局：

- 左栏：主控 Pi，不要移走，不要被 worktree 换成别的 workspace。
- 右栏：子智能体。多个子智能体用当前 workspace 的 tab 区分，每个 tab 一个子智能体。

所有 `split` / `create` / `move` / `start` 都加 `--no-focus`，保持用户焦点在主控。**禁止通过 Herdr 命令修改当前 focus 的 tab 或 pane**，不得使用 `herdr tab focus`、`herdr pane focus` 或任何等效的聚焦/切换命令；需要让用户查看子智能体时，只能告知 pane/tab 标识，由用户自行切换。

## 创建 Worktree 与启动子智能体

主控负责选择项目、分支、base 和任务边界；Herdr 负责实际创建 worktree、workspace 和 pane。不要手工执行 `git worktree add`，也不要直接在项目主目录里启动会改代码的子智能体。从命令返回的 JSON 中读取真实 ID。

需要改代码时，用 `--cwd` 创建 worktree（不要同时写 `--workspace`）：

```bash
result=$(herdr worktree create \
  --cwd <project-path> \
  --branch <branch-name> \
  --base <base-ref> \
  --label <task-label> \
  --no-focus)
```

从 JSON 读取 `worktree.path` 和误开的 `workspace_id`。立刻在当前主控 workspace 建 tab 指向这个 worktree，然后关掉误开的 workspace：

```bash
herdr tab create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --cwd <worktree.path> \
  --label <task-label> \
  --no-focus
herdr workspace close <误开的 workspace_id>
```

只读定位不要创建 worktree。第一个只读子智能体放进主控右侧：若当前主控 pane 还没有右邻，`herdr pane split --current --direction right --cwd <project-path> --no-focus`。后续子智能体一律用当前 workspace 的新 tab，不要再留着 worktree create 带出来的那个 workspace。

在目标 pane 启动 Codex 时把模型、思考级别和 full access 写在 `--` 后面：

```bash
herdr agent start <agent-name> \
  --kind codex \
  --pane <pane-id> \
  -- \
  -m gpt-5.6-sol \
  -c model_reasoning_effort="medium" \
  --sandbox danger-full-access \
  -a never
```

启动后用 `herdr agent prompt <agent-name> <task> --wait --until working --timeout 8000` 派发。prompt 成功但未进入 `working`（含 `agent_prompt_stalled`）时，不要再 prompt，改走 pane；整个流程禁止使用 `herdr tab focus`、`herdr pane focus` 或任何等效的聚焦/切换命令：

```bash
herdr pane send-text <pane-id> '<task>'
herdr pane wait-output <pane-id> --match '<任务里的独特片段>' --timeout 10000
herdr pane send-keys <pane-id> enter
herdr agent get <agent-name>
```

`send-text` 只粘贴，不提交。必须等任务文本出现在 pane 里再回车；回车打给 pane，不要用 `herdr agent send-keys`。`send-keys` 返回 ok 不等于已经提交。`get` 仍不是 `working` 就再发一次 `herdr pane send-keys <pane-id> enter`，再 `get`。看见 `working` 才能挂等待器。需要让用户查看子智能体时，只能回报 pane/tab 标识，由用户自行切换。


不要在主控 turn 中长时间同步等待。需要在 Codex settled 后唤醒主控时，用 Pi `bg_run` 执行 `herdr agent wait <agent-name>`（不要 `--until idle`，也不要短 `--timeout`），并开启完成通知和后续 turn。
