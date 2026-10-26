#!/usr/bin/env bash
# Runs Claude Code for one upgrade hop. Usage: .upgrade/run-claude.sh <hop-slug>
#
# Auth and retry behaviour are ported from ui-dev-agent's ui-gen workflow, which is proven in CI:
#   IS_MODEL_RAIL=true  -> Claude Code goes through Model Rail (/llm/v1/messages), policy from runtime.env.
#   otherwise           -> the Claude Code OAuth pool; on a usage limit, rotate to the next token
#                          and resume the same session; a bare 429 gets one patient retry first.
set -uo pipefail

slug="$1"
pkg=".upgrade"
mkdir -p "$pkg/usage" "$pkg/transcripts" "$pkg/reports" "$pkg/rotations"

# Non-secret per-run settings: model, effort, rail scope.
if [ -f "$pkg/runtime.env" ]; then set -a; . "$pkg/runtime.env"; set +a; fi
model="${CLAUDE_MODEL:-sonnet}"
[ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ] && export CLAUDE_CODE_EFFORT_LEVEL
[ -n "${MAX_THINKING_TOKENS:-}" ] && export MAX_THINKING_TOKENS

OAUTH_ROTATE=false
TOKENS=()
TOKEN_LABELS=()
token_idx=0
if [ "${IS_MODEL_RAIL:-false}" = "true" ]; then
  unset CLAUDE_CODE_OAUTH_TOKEN
  if [ -z "${MODEL_RAIL_URL:-}" ]; then echo "::error::IS_MODEL_RAIL=true but MODEL_RAIL_URL is empty"; exit 1; fi
  export ANTHROPIC_BASE_URL="$MODEL_RAIL_URL/llm"
  export ANTHROPIC_AUTH_TOKEN="${MODEL_RAIL_INTERNAL_KEY:-model-rail}"
  export ANTHROPIC_API_KEY=""
  export ANTHROPIC_CUSTOM_HEADERS="$(printf 'X-Rail-Run-Id: %s\nX-Rail-Repo: %s\nX-Rail-Agent: framework-upgrade-agent\nX-Rail-Stage: framework-upgrade\nX-Rail-Org-Id: %s\nX-Rail-Project-Id: %s\nX-Rail-Team-Id: %s\nX-Rail-Policy-Key: %s\nX-Rail-Purpose: %s' "$GITHUB_RUN_ID" "$GITHUB_REPOSITORY" "${MODEL_RAIL_ORG_ID:-}" "${MODEL_RAIL_PROJECT_ID:-}" "${MODEL_RAIL_TEAM_ID:-}" "${MODEL_RAIL_POLICY_KEY:-}" "${MODEL_RAIL_PURPOSE:-}")"
  echo "routing claude through Model Rail ($MODEL_RAIL_URL, policy=${MODEL_RAIL_POLICY_KEY:-<none>})"
else
  OAUTH_ROTATE=true
  if [ -n "${CLAUDE_CODE_OAUTH_TOKENS_JSON:-}" ]; then
    mapfile -t TOKENS < <(printf '%s' "$CLAUDE_CODE_OAUTH_TOKENS_JSON" | jq -r '.[]')
  fi
  if [ -n "${CLAUDE_CODE_OAUTH_TOKEN_LABELS_JSON:-}" ]; then
    mapfile -t TOKEN_LABELS < <(printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN_LABELS_JSON" | jq -r '.[]')
  fi
  if [ "${#TOKENS[@]}" -eq 0 ]; then TOKENS=("${CLAUDE_CODE_OAUTH_TOKEN:-}"); fi
  if [ -z "${TOKENS[0]}" ]; then
    echo "::error::No Claude Code OAuth token: the CLAUDE_CODE_OAUTH_TOKEN secret is empty. Check the step's model policy."
    exit 1
  fi
fi

token_label() {
  local i="$1" l=""
  if [ "$i" -lt "${#TOKEN_LABELS[@]}" ]; then l="${TOKEN_LABELS[$i]}"; fi
  if [ -n "$l" ]; then printf '%s' "$l"; else printf 'token #%d/%d' "$((i + 1))" "${#TOKENS[@]}"; fi
}
[ "$OAUTH_ROTATE" = "true" ] && echo "claude authenticating with the OAuth pool (${#TOKENS[@]} token(s))"

prompt="Read $pkg/AGENT.md, then do the hop described in $pkg/hops/$slug.md. Baseline results are in $pkg/baseline.json. Finish by writing $pkg/reports/$slug.json. Work autonomously until done."
usage="$pkg/usage/$slug.json"
session_id=""
tries=0
transient_used=false
rotations='[]'
while :; do
  if [ "$OAUTH_ROTATE" = "true" ]; then export CLAUDE_CODE_OAUTH_TOKEN="${TOKENS[$token_idx]}"; fi
  if [ -n "$session_id" ]; then
    run_prompt="Continue exactly where you left off and finish this hop. Finish by writing $pkg/reports/$slug.json."
    resume_args=(--resume "$session_id")
  else
    run_prompt="$prompt"
    resume_args=()
  fi
  if printf '%s' "$run_prompt" | claude --print "${resume_args[@]}" \
      --model "$model" \
      --permission-mode acceptEdits \
      --allowedTools "Bash,Read,Edit,Write,MultiEdit,Glob,Grep,TodoWrite" \
      --output-format json > "$usage" 2> "/tmp/$slug.stderr.log"; then
    status=0
  else
    status=$?
  fi
  session_id="$(jq -r '.session_id // empty' "$usage" 2>/dev/null || true)"
  { jq -r '.result // empty' "$usage" 2>/dev/null || true; cat "/tmp/$slug.stderr.log"; } > "$pkg/transcripts/$slug.log"

  is_limit=false
  msg=""
  if [ "$status" -ne 0 ] && [ "$OAUTH_ROTATE" = "true" ]; then
    msg="$(jq -r 'select(.is_error == true) | .result // empty' "$usage" 2>/dev/null || true)"
    api_status="$(jq -r '.api_error_status // empty' "$usage" 2>/dev/null || true)"
    if printf '%s' "$msg" | grep -qiE 'hit your .*limit|usage limit|session limit|weekly limit|opus limit|sonnet limit|5-hour limit|limit reached|out of extra usage'; then
      is_limit=true
    elif [ "$api_status" = "429" ]; then
      if [ "$transient_used" = "false" ]; then
        transient_used=true
        echo "::warning::transient 429 on $(token_label "$token_idx"); retrying the same token in ${CLAUDE_TRANSIENT_BACKOFF_S:-30}s"
        sleep "${CLAUDE_TRANSIENT_BACKOFF_S:-30}"
        continue
      fi
      is_limit=true
    fi
  fi
  if [ "$is_limit" = "true" ] && [ "$((tries + 1))" -lt "${#TOKENS[@]}" ]; then
    from="$(token_label "$token_idx")"
    token_idx=$(( (token_idx + 1) % ${#TOKENS[@]} ))
    tries=$((tries + 1))
    transient_used=false
    rotations="$(printf '%s' "$rotations" | jq -c --arg f "$from" --arg t "$(token_label "$token_idx")" '. + [{from: $f, to: $t}]')"
    echo "::warning::$from hit a usage limit; rotating to $(token_label "$token_idx") and resuming session ${session_id:-<none>}"
    continue
  fi
  break
done
[ "$rotations" != "[]" ] && printf '%s' "$rotations" > "$pkg/rotations/$slug.json"

if [ "$status" -ne 0 ]; then
  msg="$(jq -r '.result // empty' "$usage" 2>/dev/null || true)"
  echo "--- claude error ---"
  if [ -n "$msg" ]; then printf '%s\n' "$msg"; elif [ -s "/tmp/$slug.stderr.log" ]; then cat "/tmp/$slug.stderr.log"; else echo "(no output: likely killed by the job timeout)"; fi
  echo "::error::claude exited $status on hop $slug: ${msg:0:400}"
  exit "$status"
fi
jq -r '.result // empty' "$usage" 2>/dev/null || true
