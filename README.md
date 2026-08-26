# MGR 环境

这是 `~/mgr` 主控管理空间的可公开快照，不是业务代码仓库。它保留 Pi 配置、提示词、各级 `AGENTS.md`、主控工具源码，以及 `spaces/` 下的目录骨架，便于在新机器上恢复相同的工作环境。

## Clone 后恢复

```bash
git clone https://github.com/so2liu/mgr-env.git ~/mgr
cd ~/mgr
```

安装并配置 Pi（按所使用的 Pi 发行版文档完成），然后将 `pi-tools/pr-status/index.ts` 加入 `~/.pi/agent/settings.json` 的 `extensions` 数组。该扩展依赖 GitHub CLI：

```bash
gh auth login
cd ~/mgr/pi-tools/pr-status
npm ci
```

`pr-status` 的测试命令见其目录中的 README。业务项目仍应单独 clone 到你选择的位置，并在对应项目的独立 worktree 中开发；本仓库只保存主控环境，不包含任何业务仓库的 Git 历史或 worktree 元数据。

## 目录

- `.pi/`：根级 Pi prompts（完整保留）。
- `spaces/<name>/.pi/`：各 space 的 Pi 任务状态（完整保留）。
- `spaces/<name>/AGENTS.md`：space 规则。
- `pi-tools/pr-status/`：批量读取 GitHub PR 状态的 Pi extension 源码和离线测试。
- `plugins/mgr/`：按 Agent Plugins 1.0.0 规范打包的 `mgr` 插件，内含唯一权威的 `mgr-babysit-pr` skill。

## mgr Agent Plugin

`plugins/mgr/plugin.json` 遵循 [agent-plugins.org](https://agent-plugins.org/) 的 1.0.0 manifest；skill 位于 `plugins/mgr/skills/mgr-babysit-pr/`。规范只定义可移植目录和组件发现，不规定安装、发布或 registry。agent-plugins.org 当前是规范站点，不是这个插件的下载/安装服务，因此 `init_mgr` 会先要求确认客户端的远程安装能力和已发布来源，再进行全局安装；未发布时必须报告阻塞。发布后请使用兼容客户端文档中的用户级安装命令（Git、归档或私有 registry），安装完成后 skill 可在任意 space 发现。

## 发布边界

快照包含各 space 的 `AGENTS.md` 与 `backlog.html`；排除了临时提示和报告/HTML 产物、依赖安装目录（如 `node_modules`）、构建输出、缓存、日志、凭据、密钥、个人隐私文件，以及所有 Git 元数据。空的 space 目录使用 `.gitkeep` 保留骨架。`.pi` 内容是明确要求保留的运行状态，因此即使其中包含任务输出也按原样保留；请在继续使用前自行检查新产生的任务内容。
