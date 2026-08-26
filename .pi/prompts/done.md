---
description: 核验并合并当前任务 PR，随后关闭对应 pane
argument-hint: "[PR号或 pane/tab]"
---
完成 ${ARGUMENTS:-当前任务}：

1. 找到对应 PR、Codex、worktree、pane 和 tab；如果参数为空，就从当前任务流判断，不能猜错项目。
2. 合并前由主控亲自核验最新 head SHA、所有必需 CI、`mergeable=true`、`mergeable_state=clean`、最新 head 的 Codex 明确通过信号，以及 GraphQL `reviewThreads` 未解决数量为 0。Codex 的口头总结不能代替这些检查。
3. 只要有冲突、失败或 pending CI、未解决 thread、最新 head 缺少 Codex 终态，就不要合并；把仓库、PR、worktree 和阻塞整包交回原 Codex 处理并重新挂后台等待器。
4. 条件全部满足后执行 squash merge，不做普通 merge 或 rebase merge。
5. 确认 PR 已显示 MERGED 后，关闭对应子智能体 pane；有独立空 tab 时一并清理。不要关闭主控 pane，也不要关闭其他 space 的 pane。
6. 最后简短报告 PR、合并提交、关闭的 pane/tab，以及未完成事项。