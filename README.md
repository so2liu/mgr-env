# MGR 环境

这是 `~/mgr` 主控管理空间的可公开快照，不是业务代码仓库。它保留 Pi 配置、提示词、各级 `AGENTS.md`、主控工具源码，以及 `spaces/` 下的目录骨架，便于在新机器上恢复相同的工作环境。

主控行为规范位于 `spaces/AGENTS.md`（即 mgr 主控如何拆任务、委派 Codex、检查结果、汇报的完整规则）。mgr 根目录不保留 `AGENTS.md`，避免它作为仓库文件被 mgr 的 worktree 复制、导致 worker 误以为自己是主控。主控在 `spaces/<name>/` 下启动时，Pi 会向上逐层读到 `spaces/AGENTS.md` 与 `spaces/<name>/AGENTS.md`。

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
- `spaces/AGENTS.md`：主控行为规范（全仓库主控职责与协作方式）。
- `spaces/<name>/AGENTS.md`：各 space 的规则。
- `pi-tools/pr-status/`：批量读取 GitHub PR 状态的 Pi extension 源码和离线测试。

## 发布边界

快照包含各 space 的 `AGENTS.md` 与 `backlog.html`；排除了临时提示和报告/HTML 产物、依赖安装目录（如 `node_modules`）、构建输出、缓存、日志、凭据、密钥、个人隐私文件，以及所有 Git 元数据。空的 space 目录使用 `.gitkeep` 保留骨架。`.pi` 内容是明确要求保留的运行状态，因此即使其中包含任务输出也按原样保留；请在继续使用前自行检查新产生的任务内容。
