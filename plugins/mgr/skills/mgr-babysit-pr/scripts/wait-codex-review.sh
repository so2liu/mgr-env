#!/usr/bin/env bash
# wait-codex-review.sh — Block until PR needs attention or review is complete
#
# Usage: wait-codex-review.sh <owner/repo> <pr_number> [--ignore-check <check_name>]...
#
# Stop conditions (either one → exit 1 "review passed"):
#   A. Codex left a 👍 reaction on the PR body
#   B. All Codex review threads are resolved AND all Codex issue comments are replied
#      AND Codex is not currently reviewing (no 👀 reaction). Requires Codex to have
#      commented at least once — an empty PR with no icon means Codex hasn't woken up
#      yet; keep waiting.
#
# Exit codes:
#   0 — Unresolved Codex review thread(s) or unreplied Codex issue comment(s) exist
#       (stdout: JSON array of comment IDs)
#   1 — Review passed (condition A or B above)
#   2 — Timeout (max wait exceeded)
#   3 — Non-ignored CI check failure (stdout: JSON array of failed check names)
#   4 — Merge conflict detected
#   5 — Unresolved review thread(s) from other reviewers (stdout: JSON array of comment IDs)
#
# Notes:
#   - "Unresolved" uses GitHub's native `reviewThread.isResolved` flag.
#   - "Codex reviewed" = any Codex review thread exists on this PR (resolved or not).

set -uo pipefail

usage() {
    echo "Usage: wait-codex-review.sh <owner/repo> <pr_number> [--ignore-check <check_name>]..." >&2
    exit 64
}

(( $# >= 2 )) || usage

REPO="$1"
PR="$2"
shift 2

ignored_checks='[]'
while (( $# > 0 )); do
    case "$1" in
        --ignore-check)
            (( $# >= 2 )) || usage
            ignored_checks=$(jq -c --arg name "$2" '. + [$name] | unique' <<<"$ignored_checks")
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

OWNER="${REPO%/*}"
NAME="${REPO#*/}"

# A PR can retain reactions from earlier Codex runs. Scope all reaction
# signals to the current head commit so an old 👍 cannot approve a new head and
# an old 👀 cannot keep a completed run blocked.
HEAD_SHA=""
HEAD_COMMITTED_AT=""
INVOCATION_STARTED_AT=""
REACTION_STARTED_AT=""
OBSERVED_HEAD_SHA=""
HEAD_CHANGE_AT=""
CODEX_BOT="chatgpt-codex-connector"
resolve_head() {
    local head_sha head_committed_at
    head_sha=$(gh pr view "$PR" --repo "$REPO" --json headRefOid --jq '.headRefOid' 2>/dev/null) || return 1
    head_committed_at=$(gh api "repos/${REPO}/commits/${head_sha}" --jq '.commit.committer.date // .commit.author.date' 2>/dev/null) || return 1
    [ -n "$head_sha" ] && [ -n "$head_committed_at" ] || return 1
    if [ -n "$OBSERVED_HEAD_SHA" ] && [ "$OBSERVED_HEAD_SHA" != "$head_sha" ]; then
        # Commit metadata is not a reliable head-update timestamp (for example
        # after a force-push to an older commit). Reset reaction evidence at the
        # moment this watcher observes the new head instead.
        HEAD_CHANGE_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    fi
    OBSERVED_HEAD_SHA="$head_sha"
    HEAD_SHA="$head_sha"
    HEAD_COMMITTED_AT="$head_committed_at"
}
resolve_invocation_boundary() {
    local latest_trigger_at
    latest_trigger_at=$(gh api "repos/${REPO}/issues/${PR}/comments" --paginate --slurp 2>/dev/null \
        | jq -r --arg bot "$CODEX_BOT" '
            [.[][] | select((.user.login // "") != $bot and ((.body // "") | contains("@codex"))) | .created_at] | max // ""') || return 1
    INVOCATION_STARTED_AT="$HEAD_COMMITTED_AT"
    if [ -n "$latest_trigger_at" ] && [[ "$latest_trigger_at" > "$INVOCATION_STARTED_AT" ]]; then
        INVOCATION_STARTED_AT="$latest_trigger_at"
    fi
    # Keep the invocation boundary across watcher restarts so a current
    # reaction emitted before a restart remains valid. A head change observed
    # by this process is the only additional boundary needed for REST targets
    # that do not carry a commit SHA.
    REACTION_STARTED_AT="$INVOCATION_STARTED_AT"
    if [ -n "$HEAD_CHANGE_AT" ] && [[ "$HEAD_CHANGE_AT" > "$REACTION_STARTED_AT" ]]; then
        REACTION_STARTED_AT="$HEAD_CHANGE_AT"
    fi
}
if ! resolve_head || ! resolve_invocation_boundary; then
    echo "[babysit] WARNING: Failed to resolve current PR review boundary; waiting for a successful lookup." >&2
fi

POLL_INTERVAL="${BABYSIT_POLL_INTERVAL:-60}" # seconds between polls
MAX_POLLS="${BABYSIT_MAX_POLLS:-60}"         # max polls (~60 min)

responder_login=$(gh api user --jq '.login' 2>&1) || {
    echo "[babysit] WARNING: Failed to resolve authenticated GitHub user: $responder_login" >&2
    responder_login=""
}

poll_count=0

echo "[babysit] Watching PR #${PR} on ${REPO}"

# Single GraphQL call returns both the unresolved thread ids (split by author)
# and a boolean "has_codex_review" indicating Codex has touched this PR at all.
fetch_review_state() {
    gh api graphql \
        -f query='
          query($owner: String!, $repo: String!, $pr: Int!) {
            repository(owner: $owner, name: $repo) {
              pullRequest(number: $pr) {
                reviewThreads(first: 100) {
                  nodes {
                    isResolved
                    comments(first: 1) {
                      nodes { databaseId author { login } }
                    }
                  }
                }
                reviews(last: 100) {
                  nodes {
                    author { login }
                    commit { oid }
                    submittedAt
                  }
                }
              }
            }
          }' \
        -f owner="$OWNER" -f repo="$NAME" -F pr="$PR" \
        | jq --arg bot "$CODEX_BOT" --arg head "$HEAD_SHA" --arg after "$INVOCATION_STARTED_AT" '
            .data.repository.pullRequest as $pr
            | $pr.reviewThreads.nodes as $threads
            | {
                has_current_codex_review: ([$pr.reviews.nodes[] | select(.author.login == $bot and .commit.oid == $head and (.submittedAt // "") >= $after)] | length > 0),
                codex: [ $threads[] | select(.isResolved == false and .comments.nodes[0].author.login == $bot) | .comments.nodes[0].databaseId ],
                others: [ $threads[] | select(.isResolved == false and .comments.nodes[0].author.login != $bot) | .comments.nodes[0].databaseId ]
              }'
}

while (( poll_count < MAX_POLLS )); do
    (( poll_count++ ))

    # Refresh the head and latest @codex invocation each poll so a push or
    # retrigger starts a fresh reaction scope instead of reusing old signals.
    if ! resolve_head || ! resolve_invocation_boundary; then
        echo "[babysit] (${poll_count}/${MAX_POLLS}) Current PR review boundary is unavailable, retrying..."
        sleep "$POLL_INTERVAL"
        continue
    fi

    # --- Check 1: CI Actions status ---
    checks=$(gh pr checks "$PR" --repo "$REPO" --json name,state 2>&1)
    checks_status=$?
    if ! jq -e 'type == "array"' <<<"$checks" >/dev/null 2>&1; then
        echo "[babysit] WARNING: Failed to fetch CI checks (exit ${checks_status}): $checks" >&2
        checks="[]"
    fi

    failed_checks=$(jq -c --argjson ignored "$ignored_checks" \
        '[.[] | select(.state == "FAILURE" or .state == "ERROR") | .name | select(. as $name | $ignored | index($name) | not)]' \
        <<<"$checks" 2>/dev/null) || failed_checks="[]"

    if [ "$failed_checks" != "[]" ] && [ -n "$failed_checks" ]; then
        echo "[babysit] CI check(s) failed."
        echo "$failed_checks"
        exit 3
    fi

    pending_checks=$(jq \
        '[.[] | select(.state == "PENDING" or .state == "QUEUED" or .state == "IN_PROGRESS")] | length' \
        <<<"$checks" 2>/dev/null) || pending_checks=0

    if (( pending_checks > 0 )); then
        ci_pending=true
    else
        ci_pending=false
    fi

    # --- Check 2: Merge conflict ---
    pr_state=$(gh pr view "$PR" --repo "$REPO" --json mergeable 2>&1) || {
        echo "[babysit] WARNING: Failed to fetch PR status: $pr_state" >&2
        pr_state='{"mergeable":"UNKNOWN"}'
    }
    mergeable=$(jq -r '.mergeable // "UNKNOWN"' <<<"$pr_state")

    if [ "$mergeable" = "CONFLICTING" ]; then
        echo "[babysit] Merge conflict detected."
        exit 4
    fi

    # --- Check 3: Unresolved review threads + codex history (single GraphQL call) ---
    state=$(fetch_review_state 2>&1) || {
        echo "[babysit] WARNING: Failed to fetch review threads: $state" >&2
        state='{"has_current_codex_review":false,"codex":[],"others":[]}'
    }

    has_current_codex_review=$(echo "$state" | jq -r '.has_current_codex_review // false')
    codex_unresolved=$(echo "$state" | jq -c '.codex // []')
    others_unresolved=$(echo "$state" | jq -c '.others // []')

    if [ "$codex_unresolved" != "[]" ] && [ -n "$codex_unresolved" ]; then
        echo "[babysit] Unresolved Codex review thread(s) found."
        echo "$codex_unresolved"
        exit 0
    fi

    if [ "$others_unresolved" != "[]" ] && [ -n "$others_unresolved" ]; then
        echo "[babysit] Unresolved review thread(s) from other reviewers found."
        echo "$others_unresolved"
        exit 5
    fi

    # --- Check 4: Codex reactions (👀 reviewing, 👍 approved) ---
    # Codex may attach the reaction to the PR itself, the @codex trigger
    # comment, an inline review comment, or the review object. Looking only at
    # /issues/{pr}/reactions misses the latter three and can make babysit stop
    # while Codex is still working.
    fetch_codex_reactions() {
        local pr_reactions='[]'
        local issue_comment_reactions='[]'
        local review_comment_reactions='[]'
        local review_reactions='[]'
        pr_reactions=$(gh api "repos/${REPO}/issues/${PR}/reactions" --paginate --slurp 2>/dev/null \
            | jq --arg bot "${CODEX_BOT}[bot]" --arg after "$REACTION_STARTED_AT" \
              '[.[][] | select((.user.login // "") == $bot and (.created_at // "") >= $after) | {content, created_at}]') || pr_reactions='[]'

        # Fetch comment reactions through one GraphQL traversal. REST comment
        # list responses only contain aggregate reaction counts, while asking
        # `/reactions` once per comment creates an N+1 pattern that made large
        # PRs take minutes before the first decision.
        comment_reactions=$(gh api graphql \
            -f query='
              query($owner: String!, $repo: String!, $pr: Int!) {
                repository(owner: $owner, name: $repo) {
                  pullRequest(number: $pr) {
                    comments(last: 100) {
                      nodes { body reactions(last: 10) { nodes { content user { login } createdAt } } }
                    }
                    reviewThreads(first: 100) {
                      nodes {
                        comments(last: 10) {
                          nodes { body author { login } reactions(last: 10) { nodes { content user { login } createdAt } } }
                        }
                      }
                    }
                  }
                }
              }' \
            -f owner="$OWNER" -f repo="$NAME" -F pr="$PR" 2>/dev/null) || comment_reactions='{}'
        issue_comment_reactions=$(jq -c --arg bot "${CODEX_BOT}[bot]" --arg after "$REACTION_STARTED_AT" '
            [.data.repository.pullRequest.comments.nodes[]
             | select((.body // "") | contains("@codex"))
             | .reactions.nodes[]?
             | select((.user.login // "") == $bot and (.createdAt // "") >= $after)
             | {content: (.content | if . == "THUMBS_UP" then "+1" elif . == "EYES" then "eyes" else . end), created_at: .createdAt}]' <<<"$comment_reactions") || issue_comment_reactions='[]'
        review_comment_reactions=$(jq -c --arg bot "${CODEX_BOT}[bot]" --arg after "$REACTION_STARTED_AT" '
            [.data.repository.pullRequest.reviewThreads.nodes[].comments.nodes[]
             | select((.author.login // "") == $bot or ((.body // "") | contains("@codex")))
             | .reactions.nodes[]?
             | select((.user.login // "") == $bot and (.createdAt // "") >= $after)
             | {content: (.content | if . == "THUMBS_UP" then "+1" elif . == "EYES" then "eyes" else . end), created_at: .createdAt}]' <<<"$comment_reactions") || review_comment_reactions='[]'

        # Pull-request review reactions are exposed through GraphQL, unlike
        # review-comment reactions. Keep this query narrow to avoid traversing
        # every thread/comment reaction and exceeding GitHub's node limit.
        review_reactions=$(gh api graphql \
            -f query='
              query($owner: String!, $repo: String!, $pr: Int!) {
                repository(owner: $owner, name: $repo) {
                  pullRequest(number: $pr) {
                    # Review objects are returned in chronological order; the
                    # last page contains the newest reviews, including the
                    # current-head invocation, without traversing old history.
                    reviews(last: 100) {
                      nodes {
                        commit { oid }
                        reactions(first: 100) {
                          nodes { content user { login } createdAt }
                        }
                      }
                    }
                  }
                }
              }' \
            -f owner="$OWNER" -f repo="$NAME" -F pr="$PR" 2>/dev/null \
            | jq --arg bot "$CODEX_BOT" --arg head "$HEAD_SHA" --arg after "$REACTION_STARTED_AT" \
              '[.data.repository.pullRequest.reviews.nodes[] | select((.commit.oid // "") == $head) | .reactions.nodes[] | select((.user.login // "") == $bot and (.createdAt // "") >= $after) | {content: (.content | if . == "EYES" then "eyes" elif . == "THUMBS_UP" then "+1" else . end), created_at: .createdAt}]' 2>/dev/null) || review_reactions='[]'

        jq -cn --argjson pr "$pr_reactions" \
            --argjson issue "$issue_comment_reactions" \
            --argjson inline "$review_comment_reactions" \
            --argjson review "$review_reactions" \
            '($pr + $issue + $inline + $review) | unique_by([.content, .created_at])'
    }

    reactions=$(fetch_codex_reactions 2>&1) || {
        echo "[babysit] WARNING: Failed to fetch Codex reactions: $reactions" >&2
        reactions="[]"
    }

    has_eyes=$(echo "$reactions" | jq 'any(.[]; .content == "eyes")')
    has_thumbsup=$(echo "$reactions" | jq 'any(.[]; .content == "+1")')
    latest_eyes_at=$(echo "$reactions" | jq -r '[.[] | select(.content == "eyes") | .created_at] | max // ""')
    latest_thumbsup_at=$(echo "$reactions" | jq -r '[.[] | select(.content == "+1") | .created_at] | max // ""')

    # A terminal 👍 from the current invocation supersedes an earlier 👀 from
    # that same invocation. Codex leaves the earlier reaction in place, so
    # treating any historical 👀 as active would block completion forever.
    if [ "$has_eyes" = "true" ] && { [ "$has_thumbsup" != "true" ] || [[ "$latest_thumbsup_at" < "$latest_eyes_at" ]]; }; then
        echo "[babysit] (${poll_count}/${MAX_POLLS}) Codex is reviewing (👀)..."
        sleep "$POLL_INTERVAL"
        continue
    fi

    # --- Stop condition A: Codex 👍 approval ---
    if [ "$has_thumbsup" = "true" ]; then
        if [ "$ci_pending" = true ]; then
            echo "[babysit] (${poll_count}/${MAX_POLLS}) Codex approved (👍) but CI pending, waiting..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        echo "[babysit] Codex approved (👍). Review complete."
        exit 1
    fi

    # --- Check 5: Unreplied Codex issue comments ---
    # Codex sometimes posts reviews as issue-level comments instead of review threads.
    # Detect Codex issue comments that have no reply from the authenticated babysitter.
    issue_comments=$(gh api "repos/${REPO}/issues/${PR}/comments" 2>&1) || {
        echo "[babysit] WARNING: Failed to fetch issue comments: $issue_comments" >&2
        issue_comments="[]"
    }
    unreplied_issue_comments=$(jq -c --arg bot "${CODEX_BOT}[bot]" --arg responder "$responder_login" '
            [.[] | {id, login: .user.login}] as $all
            | ($all | map(select(.login == $responder)) | map(.id)) as $responder_comments
            | [
                $all[]
                | select(.login == $bot)
                | .id as $cid
                | select([$responder_comments[] | select(. > $cid)] | length == 0)
              ]
            | map(.id)
        ' <<<"$issue_comments" 2>/dev/null) || unreplied_issue_comments="[]"

    if [ "$unreplied_issue_comments" != "[]" ] && [ -n "$unreplied_issue_comments" ]; then
        echo "[babysit] Unreplied Codex issue comment(s) found."
        echo "$unreplied_issue_comments"
        exit 0
    fi

    # --- Check if Codex has left any issue comment (for stop condition B) ---
    has_codex_issue_comment=$(jq --arg bot "${CODEX_BOT}[bot]" \
        '[.[] | select(.user.login == $bot)] | length > 0' \
        <<<"$issue_comments" 2>/dev/null) || has_codex_issue_comment="false"
    has_current_codex_issue_comment=$(jq --arg bot "${CODEX_BOT}[bot]" --arg after "$INVOCATION_STARTED_AT" \
        '[.[] | select(.user.login == $bot and (.created_at // "") >= $after)] | length > 0' \
        <<<"$issue_comments" 2>/dev/null) || has_current_codex_issue_comment="false"
    # A historical thread/comment is not proof that the latest invocation
    # completed. The current run must leave a current-head review, a current
    # invocation issue comment, or a terminal reaction before stop condition B.
    codex_has_current_evidence="false"
    if [ "$has_current_codex_review" = "true" ] || [ "$has_current_codex_issue_comment" = "true" ] || [ "$has_thumbsup" = "true" ]; then
        codex_has_current_evidence="true"
    fi

    # --- Stop condition B: current Codex invocation reviewed + all resolved/replied + no 👀 ---
    if [ "$codex_has_current_evidence" = "true" ]; then
        if [ "$ci_pending" = true ]; then
            echo "[babysit] (${poll_count}/${MAX_POLLS}) All Codex threads resolved but CI pending, waiting..."
            sleep "$POLL_INTERVAL"
            continue
        fi
        echo "[babysit] All Codex review threads resolved, no 👀. Review complete."
        exit 1
    fi

    # --- No Codex signal yet: either not woken up, or very early ---
    if [ "$ci_pending" = true ]; then
        echo "[babysit] (${poll_count}/${MAX_POLLS}) CI pending, waiting for CI and Codex..."
    else
        echo "[babysit] (${poll_count}/${MAX_POLLS}) Waiting for Codex review to start..."
    fi
    sleep "$POLL_INTERVAL"
done

echo "[babysit] Timeout after ${MAX_POLLS} polls."
exit 2
