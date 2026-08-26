# ba 主控空间

这个 space 负责 `blade-agent`，默认项目目录是：

```text
~/code-space/blade-agent
```

也可以使用该仓库对应的独立 Git worktree。主控负责需求判断、任务拆分、委派 Codex、检查测试和 review 结果，以及决定是否创建或跟进 PR；不要把实时 worker 状态抄写到 `backlog.html`。

PR 跟进偏好：凡任务目标包含创建 PR，主控必须积极督促原 Codex 完整阅读并严格执行仓库内 `.claude/skills/babysit-pr/SKILL.md`。但必须区分两个阶段：**先完成开发、冲突解决、本地测试/类型检查、提交并推送，再进入 babysit**；开发阶段不要提前把 CI/review 意见当作输入反复打补丁，避免污染方案、扩大范围或混入无关改动。PR 创建后不能把“已开 PR”当成完成；必须持续跟进最新 head 的 CI、Codex review、GraphQL `reviewThreads`、冲突状态和必要回复。Codex 停在等待、只看概要、未回复或 resolve thread、或未对最新 head 取得明确 review 终态时，主控应主动 steer 原 Codex 继续 babysit。默认积极创建 PR 并持续 babysit，**不要合并**；只有用户明确要求合并时才允许合并，并使用 squash merge。

用户已明确规定 BA PR 的合并条件：**(1) 没有冲突且所有流水线通过；(2) Codex 对当前最新 head 给出 👍。** 用户要求检查并合并符合条件的 PR 时，以这两项为准；必须确认 👍 对应当前最新 head，随后使用 squash merge。注意：不能用评论正文中的 `👍`、`👎`、`Useful? React with 👍 / 👎` 等普通文本做判断；这类文字可能只是评论模板。必须核对 GitHub 的真实 review 状态/事件、评论作者确为 Codex、评论针对当前最新 head，并确认其内容是明确通过而非提出 P0/P1/P2 意见；只有明确 approval/通过信号才算 Codex 竖大拇指。

用户可以随时改变这个 space 的职责、项目路径或协作方式。遇到稳定的新偏好，直接修改本文件，让后续启动的 Pi 读取最新规则。
