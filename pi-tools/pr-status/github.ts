import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
export const MAX_BATCH = 20;
export type Input = string | { number: number | string; repo?: string };
export type ParsedPr = { repo: string; number: number };

export type CiSummary = { pass: number; fail: number; pending: number; skipped: number; neutral: number; unknown: number; total: number; overall: "PASS" | "FAIL" | "PENDING" | "UNKNOWN" };
export type PrStatus = {
  repo: string; number: number; state?: string; headSha?: string;
  ci?: CiSummary; conflict?: "yes" | "no" | "unknown";
  unresolvedReviewThreads?: number;
  codex?: "PASSED" | "REVIEWING" | "ACTION_REQUIRED" | "NOT_SEEN" | "UNKNOWN";
  error?: { kind: string; retryable: boolean };
};

export function parseInputs(inputs: Input[], defaultRepo?: string): ParsedPr[] {
  const out: ParsedPr[] = [], seen = new Set<string>();
  for (const raw of inputs) {
    const text = typeof raw === "string" ? raw.trim() : `${raw.repo ? `${raw.repo}#` : ""}${raw.number}`;
    const url = text.match(/^https?:\/\/github\.com\/([^/]+)\/([^/]+)\/pull\/(\d+)(?:\/.*)?$/i);
    const qualified = text.match(/^([^/#\s]+\/[^/#\s]+)#(\d+)$/);
    const numberOnly = text.match(/^#?(\d+)$/);
    const repo = url ? `${url[1]}/${url[2]}` : qualified ? qualified[1] : typeof raw === "object" && raw.repo ? raw.repo : defaultRepo;
    const n = Number(url?.[3] ?? qualified?.[2] ?? numberOnly?.[1] ?? (typeof raw === "object" ? raw.number : NaN));
    if (!repo || !/^\S+\/\S+$/.test(repo) || !Number.isSafeInteger(n) || n < 1) continue;
    const key = `${repo.toLowerCase()}#${n}`;
    if (!seen.has(key)) { seen.add(key); out.push({ repo, number: n }); }
  }
  return out;
}

function alias(repo: string, number: number) { return `pr_${repo.replace(/[^a-zA-Z0-9]/g, "_")}_${number}`; }
export function buildQuery(prs: ParsedPr[]): { query: string; variables: Record<string, unknown>; aliases: Record<string, ParsedPr> } {
  const aliases: Record<string, ParsedPr> = {};
  const selections = prs.map((pr) => { const a = alias(pr.repo, pr.number); aliases[a] = pr; return `${a}: repository(owner: ${JSON.stringify(pr.repo.split("/")[0])}, name: ${JSON.stringify(pr.repo.split("/")[1])}) { pullRequest(number: ${pr.number}) { number state headRefOid mergeable headRepository { nameWithOwner } reviewThreads(first: 100) { totalCount nodes { isResolved comments(first: 1) { nodes { author { login } } } } pageInfo { hasNextPage endCursor } } reviews(last: 100) { nodes { author { login } commit { oid } state } } statusCheckRollup { contexts(first: 100) { nodes { __typename ... on CheckRun { name status conclusion } ... on StatusContext { context state } } pageInfo { hasNextPage endCursor } } } } }`; }).join("\n");
  return { query: `query BatchPrStatus { ${selections} rateLimit { cost remaining resetAt } }`, variables: {}, aliases };
}

export async function ghToken(): Promise<string> {
  const { stdout } = await execFileAsync("gh", ["auth", "token"], { timeout: 5000, maxBuffer: 10000 });
  const token = stdout.trim();
  if (!token || /\s/.test(token)) throw new Error("gh auth token unavailable");
  return token;
}

export type Fetcher = (query: string, token: string, signal?: AbortSignal) => Promise<any>;
export async function fetchGraphql(query: string, token: string, signal?: AbortSignal): Promise<any> {
  const response = await fetch("https://api.github.com/graphql", { method: "POST", signal, headers: { authorization: `bearer ${token}`, "content-type": "application/json", accept: "application/json" }, body: JSON.stringify({ query }) });
  if (response.status === 401 || response.status === 403) throw Object.assign(new Error("GitHub permission denied"), { kind: "forbidden" });
  if (response.status === 429) throw Object.assign(new Error("GitHub rate limited"), { kind: "rate_limited" });
  if (!response.ok) throw Object.assign(new Error(`GitHub API HTTP ${response.status}`), { kind: "api" });
  return response.json();
}

function ciState(node: any): keyof Pick<CiSummary, "pass" | "fail" | "pending" | "skipped" | "neutral" | "unknown"> {
  if (!node || typeof node !== "object") return "unknown";
  if (node.__typename === "CheckRun") {
    if (["SUCCESS"].includes(node.conclusion)) return "pass";
    if (["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"].includes(node.conclusion)) return "fail";
    if (["SKIPPED"].includes(node.conclusion)) return "skipped";
    if (["NEUTRAL"].includes(node.conclusion)) return "neutral";
    if (["QUEUED", "IN_PROGRESS", "WAITING", "PENDING", null, undefined].includes(node.status) || !node.conclusion) return "pending";
  } else if (node.__typename === "StatusContext") {
    if (node.state === "SUCCESS") return "pass";
    if (["FAILURE", "ERROR"].includes(node.state)) return "fail";
    if (["PENDING"].includes(node.state)) return "pending";
    if (["EXPECTED"].includes(node.state)) return "pending";
    if (["ERROR"].includes(node.state)) return "fail";
  }
  return "unknown";
}
export function summarizeCi(nodes: any[], incomplete = false): CiSummary {
  const out: CiSummary = { pass: 0, fail: 0, pending: 0, skipped: 0, neutral: 0, unknown: 0, total: nodes.length, overall: "UNKNOWN" };
  for (const node of nodes) out[ciState(node)]++;
  if (incomplete) out.unknown++;
  out.overall = out.unknown ? "UNKNOWN" : out.fail ? "FAIL" : out.pending ? "PENDING" : "PASS";
  return out;
}

export function projectPr(node: any, pr: ParsedPr): PrStatus {
  if (!node) return { repo: pr.repo, number: pr.number, error: { kind: "not_found", retryable: false } };
  const threads = node.reviewThreads?.nodes ?? [];
  const unresolved = threads.filter((t: any) => t?.isResolved === false).length;
  const bot = "chatgpt-codex-connector";
  const codexUnresolved = threads.some((t: any) => !t?.isResolved && t?.comments?.nodes?.[0]?.author?.login === bot);
  const reviewingHead = (node.reviews?.nodes ?? []).some((r: any) => r?.author?.login === bot && r?.commit?.oid === node.headRefOid && r?.state === "PENDING");
  const changesRequested = (node.reviews?.nodes ?? []).some((r: any) => r?.author?.login === bot && r?.commit?.oid === node.headRefOid && r?.state === "CHANGES_REQUESTED");
  const reviewedHead = (node.reviews?.nodes ?? []).some((r: any) => r?.author?.login === bot && r?.commit?.oid === node.headRefOid && r?.state === "APPROVED");
  return { repo: pr.repo, number: pr.number, state: node.state, headSha: node.headRefOid, ci: summarizeCi(node.statusCheckRollup?.contexts?.nodes ?? [], false), conflict: node.mergeable === "CONFLICTING" ? "yes" : node.mergeable === "MERGEABLE" ? "no" : "unknown", unresolvedReviewThreads: unresolved, codex: codexUnresolved || changesRequested ? "ACTION_REQUIRED" : reviewingHead ? "REVIEWING" : reviewedHead ? "PASSED" : "NOT_SEEN" };
}
