新任务：处理 PR #1897，解决冲突，继续 babysit-pr，满足条件后合并。

项目：/root/code-space/blade-agent
PR：https://github.com/blade-hq/blade-agent/pull/1897

要求：
1. 使用独立 worktree，基于 PR 当前分支；不要在主项目目录直接修改。
2. **先完成开发/冲突解决和本地验证，再进入 babysit 阶段**：先检查 PR 当前 head、base 和冲突，解决与最新 `origin/main` 的真实冲突，保留 PR 目标，避免引入无关改动；跑受影响测试、类型检查/构建和必要的完整检查。此阶段不要把 CI/review 反馈当作开发输入反复处理，避免污染方案和混入无关改动。
3. 开发改动完成、测试通过并推送后，再完整阅读仓库 `.claude/skills/babysit-pr/SKILL.md` 并进入 babysit：跟进最新 head 的 CI、Codex review、GraphQL reviewThreads、mergeable/clean；有意见才判断、修复、测试、回复、resolve。
5. 用户已明确要求 merge：只有在最新 head SHA、必需 CI、Codex review 明确终态、GraphQL 未解决 threads=0、mergeable=MERGEABLE/CLEAN 均亲自复核后，才执行 squash merge；不要在条件不满足时合并。
6. 合并后复核 PR 状态和合并提交；回报冲突处理、测试、review/CI、merge commit。