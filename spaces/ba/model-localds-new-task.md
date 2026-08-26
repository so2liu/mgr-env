新任务：调查并修复用户界面显示模型 `localds/deepseek-v4-flash-0731` 的问题。

项目：/root/code-space/blade-agent
要求：
1. 使用新的独立 worktree，基于最新 origin/main；不要复用其他任务的 worktree、分支或 Codex agent。
2. 定位 `localds/deepseek-v4-flash-0731` 以及 `localds` 的来源，区分系统配置/环境变量、模型注册信息、测试 fixture、展示拼接逻辑和产品代码硬编码。
3. 如果产品代码硬编码了 `localds` 或该模型标识，移除硬编码，改为使用系统配置/实际模型标识；不能破坏 provider/model 的合法解析。
4. 如果只是测试或环境配置，明确说明来源，并判断是否错误地泄漏到了用户可见展示；必要时修正展示逻辑。
5. 补充回归测试并运行相关测试。
6. 提交代码、推送并创建 PR；PR 创建后严格按仓库 `.claude/skills/babysit-pr/SKILL.md` 持续 babysit CI、Codex review、GraphQL reviewThreads、冲突和必要回复。不要合并；只有用户明确要求合并时才允许 squash merge。

回报：根因、修改文件、测试结果、commit、PR 链接/编号和 babysit 状态。