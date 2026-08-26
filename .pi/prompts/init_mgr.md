---
description: 首次使用 mgr 时准备 Codex 与插件，并将 workspace 重命名为 ba、misc、tmp
---
首次使用 mgr 时，先确认 Codex CLI 可用，再准备 mgr Agent Plugin：

1. 执行 `command -v codex` 和 `codex --version`。若未安装，按 Codex CLI 官方文档安装并重新验证；若安装失败，告知用户 mgr 依赖 Codex CLI，停止后续步骤。
2. 阅读 https://agent-plugins.org/ 当前文档，确认兼容客户端提供从已发布 Git、归档或 registry 来源进行用户级/全局安装的命令。该站点定义插件格式，但规范不定义安装命令，也不是本插件的下载源；不要从当前本地 checkout 安装，也不要伪造安装成功。
3. 使用兼容客户端的实际远程安装命令安装已发布的 `mgr` plugin，随后验证客户端能发现 `mgr-babysit-pr`，确认它在任意 space 可用。若插件尚未发布或客户端没有远程安装入口，报告阻塞并停止后续步骤。

把当前 Herdr 会话中对应 mgr 主控空间的 workspace 重命名为：

- `/Users/yangliu35/mgr/spaces/ba` → `ba`
- `/Users/yangliu35/mgr/spaces/misc` → `misc`
- `/Users/yangliu35/mgr/spaces/tmp` → `tmp`

执行要求：

1. 先用 `herdr pane list` 或 `herdr workspace list` 根据 pane 的 `cwd` 确认 workspace ID，不要假设 ID 永远固定。
2. 只修改上述三个 space 对应的 workspace label，不要修改 workspace 内的 tab 名称，也不要碰其他 workspace。
3. 对每个 workspace 执行：`herdr workspace rename <workspace-id> <label>`。
4. 执行后用 `herdr workspace list` 复核三个 workspace 的 label，并简要汇报结果。
5. 不要创建、关闭、聚焦 workspace 或 pane，也不要修改项目文件。
