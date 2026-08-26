---
description: 检查指定 PR、agent、pane 或 tab，并督促原 Codex 推进
argument-hint: "<PR号|agent|pane|tab> [检查重点]"
---
检查 `$1`。补充要求：${@:2}

1. 解析目标对应的项目、PR、agent、pane、tab 和 worktree；有歧义时先用 Herdr/GitHub 实际状态消歧，不要靠当前焦点猜。
2. 主控做快速状态检查：agent 是否 working/idle/done/blocked，PR 是否有失败或 pending CI、冲突、未解决 review thread、最新 head 的 Codex 明确终态，worktree 是否有未提交改动。
3. 判断是否需要更深入的 Codex 介入，包括根因排查、处理 CI/review、解决冲突、DeepSeek 复核或补充验证。需要时必须复用该任务流原 Codex/pane/worktree，把明确的下一步动作发进去并确认进入 working；不要由主控自己查完或改业务代码。
4. agent 若停在计划、欢迎页、等待输入或无真实阻塞的 idle 状态，立即督促它执行下一步；确认 working 后挂 `herdr agent wait <agent-name>` 后台等待器。
5. 若目标已完成或 PR 已合并，报告结论和是否应关闭 pane；没有用户授权时不要合并 OPEN PR。
6. 输出只写检查结果、采取的动作、当前阻塞和下一次通知方式。