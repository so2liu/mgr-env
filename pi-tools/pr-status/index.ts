import { Type } from "@earendil-works/pi-ai";
import { defineTool, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { buildQuery, fetchGraphql, ghToken, MAX_BATCH, parseInputs, projectPr, type Input, type ParsedPr, type PrStatus } from "./github.ts";

const Params = Type.Object({
  prs: Type.Array(Type.Union([Type.String(), Type.Object({ number: Type.Union([Type.String(), Type.Integer()]), repo: Type.Optional(Type.String()) })]), { description: "PR 编号、owner/repo#编号 或完整 GitHub PR URL" }),
  defaultRepo: Type.Optional(Type.String({ description: "未带仓库的编号使用的 owner/repo" })),
});

export const prStatusTool = defineTool({
  name: "pr_status",
  label: "批量 PR 状态",
  description: "只读地快速检查多个 GitHub PR。一次传入多个编号/URL，返回紧凑 JSON：CI 聚合、合并冲突、未解决 review thread 数和当前 head 的 Codex 状态。需要比较多个 PR 的状态时调用；不要用于读取评论正文、日志、diff 或修改 PR。",
  promptSnippet: "批量读取多个 PR 的紧凑 CI、冲突、review 和 Codex 状态",
  promptGuidelines: ["Use pr_status when comparing two or more GitHub pull requests; do not call gh once per PR."],
  parameters: Params,
  async execute(_id, params, signal) {
    const parsed = parseInputs(params.prs as Input[], params.defaultRepo);
    if (!parsed.length) throw new Error("没有可识别的 PR 输入");
    const chunks: typeof parsed[] = [];
    for (let i = 0; i < parsed.length; i += MAX_BATCH) chunks.push(parsed.slice(i, i + MAX_BATCH));
    const items: PrStatus[] = [];
    let token: string;
    try { token = await ghToken(); } catch { return { content: [{ type: "text", text: JSON.stringify({ items: [], summary: { requested: parsed.length, errors: parsed.length }, error: { kind: "auth", retryable: false } }) }], details: {} }; }
    for (const chunk of chunks) {
      const { query, aliases } = buildQuery(chunk);
      let payload: any;
      try { payload = await fetchGraphql(query, token, signal); } catch (error: any) { for (const pr of chunk) items.push({ repo: pr.repo, number: pr.number, error: { kind: error?.kind ?? "network", retryable: error?.kind === "rate_limited" || error?.kind === "api" } }); continue; }
      for (const [a, pr] of Object.entries(aliases)) {
        const errors = payload.errors?.filter((e: any) => String(e.path?.[0]) === a);
        if (errors?.length) { items.push({ repo: pr.repo, number: pr.number, error: { kind: "graphql", retryable: false } }); continue; }
        const node = payload.data?.[a]?.pullRequest;
        if (!node) { items.push(projectPr(node, pr)); continue; }
        try {
          await fetchRemainingPages(node, pr, token, signal);
          items.push(projectPr(node, pr));
        } catch (error: any) {
          items.push({ repo: pr.repo, number: pr.number, error: { kind: error?.kind ?? "pagination", retryable: error?.kind === "rate_limited" || error?.kind === "api" } });
        }
      }
    }
    items.sort((a, b) => parsed.findIndex(p => p.repo === a.repo && p.number === a.number) - parsed.findIndex(p => p.repo === b.repo && p.number === b.number));
    const summary = { requested: parsed.length, returned: items.filter(i => !i.error).length, errors: items.filter(i => i.error).length, ciPass: items.filter(i => i.ci?.overall === "PASS").length, conflicts: items.filter(i => i.conflict === "yes").length, withUnresolved: items.filter(i => (i.unresolvedReviewThreads ?? 0) > 0).length };
    const result = { items, summary };
    return { content: [{ type: "text", text: JSON.stringify(result) }], details: {} };
  },
});

async function fetchRemainingPages(node: any, pr: ParsedPr, token: string, signal?: AbortSignal) {
  let threadCursor = node.reviewThreads?.pageInfo?.endCursor;
  let contextCursor = node.statusCheckRollup?.contexts?.pageInfo?.endCursor;
  for (let page = 0; page < 10 && (node.reviewThreads?.pageInfo?.hasNextPage || node.statusCheckRollup?.contexts?.pageInfo?.hasNextPage); page++) {
    const tArg = node.reviewThreads?.pageInfo?.hasNextPage ? `, after: ${JSON.stringify(threadCursor)}` : "";
    const cArg = node.statusCheckRollup?.contexts?.pageInfo?.hasNextPage ? `, after: ${JSON.stringify(contextCursor)}` : "";
    const owner = pr.repo.split("/")[0], name = pr.repo.split("/")[1];
    const query = `query NextPage { repository(owner: ${JSON.stringify(owner)}, name: ${JSON.stringify(name)}) { pullRequest(number: ${pr.number}) { reviewThreads(first: 100${tArg}) { nodes { isResolved comments(first: 1) { nodes { author { login } } } } pageInfo { hasNextPage endCursor } } statusCheckRollup { contexts(first: 100${cArg}) { nodes { __typename ... on CheckRun { name status conclusion } ... on StatusContext { context state } } pageInfo { hasNextPage endCursor } } } } }`;
    const next = await fetchGraphql(query, token, signal);
    const p = next.data?.repository?.pullRequest;
    if (!p) throw Object.assign(new Error("pagination response missing PR"), { kind: "api" });
    node.reviewThreads.nodes.push(...(p.reviewThreads?.nodes ?? []));
    node.reviewThreads.pageInfo = p.reviewThreads?.pageInfo;
    if (node.statusCheckRollup?.contexts) {
      node.statusCheckRollup.contexts.nodes.push(...(p.statusCheckRollup?.contexts?.nodes ?? []));
      node.statusCheckRollup.contexts.pageInfo = p.statusCheckRollup?.contexts?.pageInfo;
    }
    threadCursor = node.reviewThreads?.pageInfo?.endCursor;
    contextCursor = node.statusCheckRollup?.contexts?.pageInfo?.endCursor;
  }
  if (node.reviewThreads?.pageInfo?.hasNextPage || node.statusCheckRollup?.contexts?.pageInfo?.hasNextPage) throw Object.assign(new Error("pagination limit reached"), { kind: "api" });
}

export default function (pi: ExtensionAPI) { pi.registerTool(prStatusTool); }
