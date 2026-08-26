#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
wait_script="${WAIT_SCRIPT:-$root/wait-codex-review.sh}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
calls="$tmp/calls"

cat >"$tmp/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_CALLS"
if [[ "$*" == "api user"* ]]; then echo '{"login":"reviewer"}'; exit 0; fi
if [[ "$*" == "pr view"* && "$*" == *"headRefOid"* ]]; then
  n=$(grep -c 'headRefOid' "$FAKE_CALLS" || true)
  if [[ "${FAKE_SCENARIO:-}" == head-update && $n -gt 1 ]]; then echo 'new-head'; else echo 'head-1'; fi
  exit 0
fi
if [[ "$*" == "pr view"* && "$*" == *"mergeable"* ]]; then echo '{"mergeable":"MERGEABLE"}'; exit 0; fi
if [[ "$*" == *"commits/head-1"* || "$*" == *"commits/new-head"* ]]; then echo '2026-08-21T15:30:00Z'; exit 0; fi
if [[ "$*" == *"issues/1831/comments"* ]]; then
  if [[ "${FAKE_SCENARIO:-}" == invocation ]]; then echo '[ [{"body":"@codex","created_at":"2026-08-23T00:00:00Z","user":{"login":"reviewer"}}] ]';
  else echo '[ [] ]'; fi
  exit 0
fi
if [[ "$*" == *"issues/1831/reactions"* ]]; then
  case "${FAKE_SCENARIO:-thumb}" in
    thumb|head-update) echo '[[{"content":"+1","created_at":"2026-08-21T15:34:59Z","user":{"login":"chatgpt-codex-connector[bot]"}}]]';;
    eyes-thumb) echo '[[{"content":"eyes","created_at":"2026-08-23T00:01:00Z","user":{"login":"chatgpt-codex-connector[bot]"}},{"content":"+1","created_at":"2026-08-23T00:02:00Z","user":{"login":"chatgpt-codex-connector[bot]"}}]]';;
    *) echo '[[ ]]';;
  esac
  exit 0
fi
if [[ "$*" == "pr checks"* ]]; then echo '[]'; exit 0; fi
if [[ "$*" == "api graphql"* ]]; then
  if [[ "$*" == *"comments(last: 100)"* ]]; then echo '{"data":{"repository":{"pullRequest":{"comments":{"nodes":[]},"reviewThreads":{"nodes":[]}}}}}';
  else echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]},"reviews":{"nodes":[]}}}}}'; fi
  exit 0
fi
if [[ "$*" == *"pulls/1831/comments"* ]]; then echo '[]'; exit 0; fi
echo '[]'
GH
chmod +x "$tmp/bin/gh"
cat >"$tmp/bin/sleep" <<'SLEEP'
#!/usr/bin/env bash
exit 0
SLEEP
chmod +x "$tmp/bin/sleep"

run_case() {
  local scenario=$1 expected=$2 max_polls=${3:-1}
  : >"$calls"
  set +e
  FAKE_CALLS="$calls" FAKE_SCENARIO="$scenario" PATH="$tmp/bin:$PATH" \
    BABYSIT_POLL_INTERVAL=0 BABYSIT_MAX_POLLS="$max_polls" \
    bash "$wait_script" blade-hq/blade-agent 1831 >"$tmp/out" 2>"$tmp/err"
  local status=$?
  set -e
  [[ $status == "$expected" ]] || { cat "$tmp/out" "$tmp/err"; echo "${scenario}: expected $expected, got $status" >&2; return 1; }
}

# A restarted watcher must accept a terminal reaction created on the current head.
run_case thumb 1
# A new invocation makes the older terminal reaction invalid.
run_case invocation 2
# A head update invalidates the older head's reaction while the watcher is alive.
run_case head-update 2 2
# A newer terminal reaction supersedes an earlier 👀 reaction.
run_case eyes-thumb 1

# Keep the bounded query on the newest reactions, so an old busy comment cannot
# hide a current terminal signal behind the first page.
if ! grep -q 'reactions(last: 10)' "$wait_script"; then
  echo 'reaction query does not request the newest bounded page' >&2
  exit 1
fi

# No per-comment reaction endpoint may be issued (the old implementation was N+1).
if grep -Eq 'issues/comments/.*/reactions|pulls/comments/.*/reactions' "$calls"; then
  echo 'per-comment reaction endpoint detected' >&2
  exit 1
fi
echo 'wait-codex-review fixture tests passed'
