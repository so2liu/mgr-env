新任务：排查“记忆的自动注入是否丢了，或者 UI 没展示”的问题，并修复后创建 PR、持续 babysit，不合并。

项目：/root/code-space/blade-agent

用户关切：记忆（memory）的自动注入可能丢失，或只是 UI 没有展示；项目存在多个视图，必须全面覆盖，不能只检查单一 Chat 视图。

要求：
1. 使用新的独立 worktree，基于最新 origin/main；不要复用其他任务的 worktree、分支或 Codex agent。
2. 全链路调查：记忆的产生/存储、自动注入到模型上下文的后端/运行时路径、Socket/HTTP 事件、前端状态与展示路径。
3. 逐一核对所有相关视图/模式（至少 Chat 主视图、Lite/其他 Chat 视图、历史/恢复会话、移动端或嵌入视图，如仓库存在），区分“实际未注入”和“已注入但 UI 未展示”。
4. 使用 git 历史和回归测试定位根因；如发现最近改动导致回归，明确指出提交/文件。
5. 修复真实问题，避免只加 UI 假象；必要时同时修复后端注入与前端展示，并为每个受影响视图补回归测试。
6. 运行相关后端、前端测试和类型检查；记录环境限制。
7. 提交、推送并创建 PR；PR 创建后严格按 `.claude/skills/babysit-pr/SKILL.md` 持续跟进 CI、Codex review、GraphQL reviewThreads、冲突和必要回复。不要合并；只有用户明确要求合并时才允许 squash merge。

回报：根因（注入丢失/UI隐藏/两者）、涉及视图、修改文件、测试结果、commit、PR 链接/编号和 babysit 状态。