---
description: 报告当前 space 的所有子智能体 pane 状态
---
报告当前 space 名下所有已开启的子智能体 pane。直接读取 Herdr 的 agent、pane、tab、worktree 和 GitHub 实际状态，不要依赖 backlog 或旧总结。

每个 pane 至少报告：
- pane/tab 标识、agent 名称、项目/worktree；
- 当前状态：working、idle、done、blocked 或异常；
- 是否有关联 PR；有的话列 PR 号、OPEN/MERGED/CLOSED、CI、冲突、未解决 review thread 数；
- 距离该 agent 上次交付、状态变化或最终输出过去多久；说明采用了哪个时间点；
- 是否应该关闭，并给一句具体理由。

先列正在工作和阻塞项，再列仍需保留的 OPEN PR，最后列建议关闭的 pane。已经合并的 PR 不再做第二轮交付核验，确认已 MERGED 后直接标为应关闭。最后汇总：运行中多少、等待 PR 多少、建议关闭多少。