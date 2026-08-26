---
description: 安装 mgr Agent Plugin 并将 mgr 主控空间的 Herdr workspace 重命名为 ba、misc、tmp
---
在执行 workspace 重命名之前，确认并完成 mgr Agent Plugin 的全局安装：

1. 先阅读 https://agent-plugins.org/ 的当前文档。该站点定义 `plugin.json`、`skills/<skill>/SKILL.md` 等格式，但规范明确把安装、分发和更新留给兼容客户端；截至目前站点没有统一的 `plugin install`/`agent plugin add` 命令或公共 registry。
2. 因此不要声称可以直接从 agent-plugins.org 安装，也不要安装本地路径。只有在所用客户端提供了明确的远程 Git、归档或 registry 安装入口、且该插件已发布到该入口后，才按客户端文档执行用户级/全局安装（例如其 Git URL 安装命令），来源应是已发布的 `mgr` plugin，而不是当前本地 checkout。
3. 安装成功后验证客户端能发现 `mgr-babysit-pr`；它应在任意 space 可用。若尚未发布或客户端没有远程安装入口，报告阻塞并给出待发布的 Git/私有 registry 替代，不要伪造成功。

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
