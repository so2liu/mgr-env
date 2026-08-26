请重新筛选 blade-agent 的开放 PR，目标是找出真正满足合并条件的 PR：
1. 当前 head 无冲突，mergeable=MERGEABLE 且 clean；
2. 所有必需且非 skipped 的 CI/checks 已通过；
3. 必须有 GitHub 真实 review approval/明确通过状态，且作者确为 Codex；不能把评论正文中的“👍”“Useful? React with 👍 / 👎”当作 approval；
4. Codex 的 review/approval 必须针对当前最新 head，且没有该 head 上未处理的 P0/P1/P2 review 意见；
5. GraphQL reviewThreads 未解决数为 0。

请使用 gh/GitHub API 逐个检查当前开放 PR，输出：符合条件的 PR 编号、URL、head SHA、mergeable 状态、CI 状态、真实 Codex review 状态、未解决 thread 数；并列出被排除的 PR 及排除原因。只读，不修改代码，不合并 PR。完整调查结束后回报。