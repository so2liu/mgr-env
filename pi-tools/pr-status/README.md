# `pr_status` Pi 主控工具

这是 `~/mgr` 管理的 Pi extension，只读批量读取 GitHub PR 的紧凑状态。它不属于任何业务仓库，也不会启动逐 PR 的 `gh` 命令；只调用一次 `gh auth token` 取得 token，随后按仓库用 GraphQL alias 批量查询。

## 安装/全局加载

源码入口是 `/Users/yangliu35/mgr/pi-tools/pr-status/index.ts`。临时试用：

```bash
pi -e /Users/yangliu35/mgr/pi-tools/pr-status/index.ts
```

持久启用：在 `~/.pi/agent/settings.json` 的 `extensions` 数组加入该绝对路径。全局 settings 对从 `~/mgr/spaces/ba`、`misc`、`tmp` 启动的 Pi 生效，不要复制到各 space。

需要 `gh auth token` 可用，并授予 GitHub token 读取目标仓库、checks 和 reviews 的权限。token 只在进程内用于 Authorization header，不写入结果或日志。

## 输入

```json
{"prs":["123","blade-hq/blade-agent#1910","https://github.com/blade-hq/blade-agent/pull/1911"],"defaultRepo":"blade-hq/blade-agent"}
```

支持编号、`owner/repo#number`、GitHub PR URL；重复项去重并保持首次出现顺序。默认单批最多 20 项，超过后分块；无效输入会被忽略，全部无效则工具报错。

## 输出契约

结果是稳定 JSON：每项含 `repo`、`number`、`state`、`headSha`、`ci`（`pass/fail/pending/skipped/neutral/unknown/total/overall`）、`conflict`（`yes/no/unknown`）、`unresolvedReviewThreads`、`codex`（`PASSED/REVIEWING/ACTION_REQUIRED/NOT_SEEN/UNKNOWN`）或局部 `error`。另有 `summary` 总计。不会返回评论正文、日志、diff、check URL 或敏感字段。

`UNKNOWN` 是保守结果：GitHub 的 `mergeable` 异步计算未完成、check/review connection 未完整分页、权限/API 部分错误时都不能当作通过或无冲突。当前 Codex 状态只依据当前 head 的 Codex review/thread 证据；没有证据返回 `NOT_SEEN`，不会猜测 `PASSED`。

## 限制

GraphQL contexts 和 review threads 默认各取 100 个节点，存在下一页时工具会按 cursor 继续请求，最多 10 页；达到上限或分页失败时该 item 返回局部错误。fork 的 head 仓库删除不影响 base PR 元数据读取，但 head SHA 可能仍是唯一可用标识。每个 item 独立记录 not found/forbidden/rate limit/GraphQL 错误，不拖垮其他 PR。

## 本地测试

```bash
cd /Users/yangliu35/mgr/pi-tools/pr-status
/Users/yangliu35/GitHub/pi-mono/node_modules/.bin/vitest --run
```

测试完全离线，覆盖输入去重、alias query、CheckRun/StatusContext 聚合、分页不完整、UNKNOWN、未解决 thread、缺失 PR 和敏感字段过滤。
