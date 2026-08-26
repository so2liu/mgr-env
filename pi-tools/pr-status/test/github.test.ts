import { describe, expect, it } from "vitest";
import { buildQuery, parseInputs, projectPr, summarizeCi } from "../github.ts";

describe("PR input normalization", () => {
  it("supports URLs, qualified and default-repo numbers with stable de-duping", () => {
    expect(parseInputs(["12", "#12", "acme/app#13", "https://github.com/acme/app/pull/14/files", "14"], "acme/app")).toEqual([
      { repo: "acme/app", number: 12 }, { repo: "acme/app", number: 13 }, { repo: "acme/app", number: 14 },
    ]);
  });
});

describe("GraphQL projection", () => {
  it("uses aliases and projects check union states without sensitive fields", () => {
    const { query, aliases } = buildQuery([{ repo: "acme/app", number: 1 }, { repo: "acme/app", number: 2 }]);
    expect(Object.keys(aliases)).toHaveLength(2);
    expect(query).toContain("pr_acme_app_1:");
    expect(query).toContain("... on CheckRun");
    expect(query).not.toMatch(/\bbody\b|detailsUrl|\btext\b|\bdiff\b/i);
  });

  it("counts pass/fail/pending/skipped/neutral/unknown and incomplete pages", () => {
    const nodes = [
      { __typename: "CheckRun", status: "COMPLETED", conclusion: "SUCCESS" },
      { __typename: "CheckRun", status: "COMPLETED", conclusion: "FAILURE" },
      { __typename: "CheckRun", status: "IN_PROGRESS", conclusion: null },
      { __typename: "CheckRun", status: "COMPLETED", conclusion: "SKIPPED" },
      { __typename: "CheckRun", status: "COMPLETED", conclusion: "NEUTRAL" },
      { __typename: "StatusContext", state: "EXPECTED" },
      { __typename: "StatusContext", state: "SUCCESS" },
    ];
    expect(summarizeCi(nodes, true)).toEqual({ pass: 2, fail: 1, pending: 2, skipped: 1, neutral: 1, unknown: 1, total: 7, overall: "UNKNOWN" });
  });

  it("keeps unresolved count and conservative Codex state", () => {
    const result = projectPr({
      number: 4, state: "OPEN", headRefOid: "abc", mergeable: "UNKNOWN",
      reviewThreads: { totalCount: 3, nodes: [
        { isResolved: false, comments: { nodes: [{ author: { login: "chatgpt-codex-connector" } }] } },
        { isResolved: false, comments: { nodes: [{ author: { login: "reviewer" } }] } },
        { isResolved: true, comments: { nodes: [{ author: { login: "reviewer" } }] } },
      ], pageInfo: { hasNextPage: false } },
      reviews: { nodes: [] }, statusCheckRollup: { contexts: { nodes: [], pageInfo: { hasNextPage: false } } },
    }, { repo: "acme/app", number: 4 });
    expect(result.unresolvedReviewThreads).toBe(2);
    expect(result.codex).toBe("ACTION_REQUIRED");
    expect(result.conflict).toBe("unknown");
    expect(JSON.stringify(result)).not.toMatch(/reviewer|body|comment/i);
  });

  it("represents missing PR as item-local error", () => {
    expect(projectPr(null, { repo: "acme/app", number: 99 })).toEqual({ repo: "acme/app", number: 99, error: { kind: "not_found", retryable: false } });
  });
});
