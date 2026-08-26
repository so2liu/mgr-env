# ba 主控空间

这个 space 负责 `blade-agent`，默认项目目录是：

```text
~/code-space/blade-agent
```

也可以使用该仓库对应的独立 Git worktree。主控负责需求判断、任务拆分、委派 Codex、检查测试和 review 结果，以及决定是否创建或跟进 PR；不要把实时 worker 状态抄写到 `backlog.html`。

用户可以随时改变这个 space 的职责、项目路径或协作方式。遇到稳定的新偏好，直接修改本文件，让后续启动的 Pi 读取最新规则。
