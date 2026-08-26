# mgr Agent Plugin

这是按 [Agent Plugins 1.0.0](https://agent-plugins.org/specification) 打包的 MGR 插件。根目录的 `plugin.json` 是唯一 manifest；`skills/` 下的每个直接子目录是一个可发现的 Agent Skill。

## 内容

- `skills/mgr-babysit-pr/SKILL.md`：持续监控 Codex PR review、CI、冲突和评论回复。
- `skills/mgr-babysit-pr/scripts/wait-codex-review.sh`：轮询脚本，保留 `--ignore-check` 和 0–5 退出码约定。
- `skills/mgr-babysit-pr/scripts/test_wait-codex-review.sh`：离线脚本行为校验。

脚本使用自身的 `$BASH_SOURCE` 解析目录，因此从任意当前目录调用都不会依赖调用者的工作目录。

## 安装与发布边界

Agent Plugins 规范只定义插件目录、manifest 和组件发现；安装、分发、启用和更新由兼容客户端决定。agent-plugins.org 当前是规范/文档站点，没有提供可直接执行的 `plugin install` 命令或公共 registry，因此不能把该域名当作这个插件的下载源，也不应伪造“全局安装成功”。

发布本插件后，应使用所用客户端的安装机制从一个可访问的 Git 仓库、发布归档或私有 registry 安装。例如客户端若支持 Git 引用，可使用本仓库的 `plugins/mgr` 子目录（或单独发布的插件仓库）；客户端安装到用户级插件目录后，`mgr-babysit-pr` 即可在任意 space 被发现。客户端的具体命令以其文档为准。

## 迭代

这里的 skill 是唯一权威源。更新 babysit-pr 行为时只修改本插件内的 skill 和脚本，再按语义版本发布；不要在 blade-agent 或其他仓库维护副本。来源脚本曾位于 blade-agent 的 `.claude/skills/babysit-pr`，本插件只保留整理后的独立副本。
