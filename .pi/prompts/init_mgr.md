---
description: 将 mgr 主控空间的 Herdr workspace 重命名为 ba、misc、tmp
---
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
