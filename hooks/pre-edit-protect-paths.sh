#!/usr/bin/env bash
# PreToolUse hook for Edit / Write / MultiEdit. Refuses edits to files an agent should never
# change on its own initiative.
#
# The list is short on purpose. A protected-path list that covers half the repository trains
# people to bypass it, and the bypass usually disarms every other guard at the same time.
#
# Input : the tool call as JSON on stdin (Claude Code passes .tool_input.file_path)
# Output: exit 0 to allow, exit 2 with a reason to block
#
# Self-test: ./pre-edit-protect-paths.sh --selftest
set -uo pipefail

CONFIRM_TOKEN="${AGENT_GOVERNANCE_CONFIRM:-I-HAVE-A-BACKUP}"

match_protected() {
  local path="$1"

  case "$path" in
    # Allow-first: templates and documentation ABOUT env vars are not env files. A guard that
    # blocks .env.example teaches people to bypass it, and the bypass disarms everything else.
    *.env.example|*.env.sample|*.env.dist|*.env.template|*.md|*.txt)
      return 1 ;;
    *.env|*.env.*|*/.env|*/.env.*)
      echo 'env-file|Environment files hold credentials. A diff of one belongs in a human review, not a tool call.'; return 0 ;;
    */.git/*|.git/*)
      echo 'git-internals|Editing .git by hand corrupts state that has no undo.'; return 0 ;;
    *id_rsa*|*id_ed25519*|*.pem|*.key|*.p12|*.pfx|*/.ssh/*)
      echo 'credential|Private key material.'; return 0 ;;
    *composer.lock|*package-lock.json|*yarn.lock|*pnpm-lock.yaml|*Gemfile.lock|*poetry.lock|*Cargo.lock)
      echo 'lockfile|A lockfile is generated, never edited. Change the manifest and let the tool resolve it.'; return 0 ;;
    */.github/workflows/*)
      echo 'ci-config|CI configuration is the thing that checks the work; it does not get edited by the work.'; return 0 ;;
    */migrations/*)
      # Only ALREADY-APPLIED migrations are dangerous, and a hook cannot know which those are.
      # So this one warns by blocking and lets the token through — the operator decides.
      echo 'migration|Editing a migration that has already run puts schema and history out of step.'; return 0 ;;
  esac
  return 1
}

check_path() {
  local path="$1" hit id why
  hit=$(match_protected "$path") || return 0
  id=${hit%%|*}; why=${hit#*|}
  if [ "${AGENT_GOVERNANCE_ALLOW_PROTECTED:-}" = "$CONFIRM_TOKEN" ]; then return 0; fi
  printf 'BLOCKED (%s): %s\n' "$id" "$why" >&2
  printf 'Path: %s\n' "$path" >&2
  printf 'A human who intends this sets AGENT_GOVERNANCE_ALLOW_PROTECTED=%s for the session.\n' "$CONFIRM_TOKEN" >&2
  return 2
}

selftest() {
  local fail=0 pass=0
  must_block() { if check_path "$1" 2>/dev/null; then printf '  MISS   %s\n' "$1"; fail=$((fail+1)); else pass=$((pass+1)); fi; }
  must_allow() { if check_path "$1" 2>/dev/null; then pass=$((pass+1)); else printf '  FALSE+ %s\n' "$1"; fail=$((fail+1)); fi; }

  must_block '/app/.env'
  must_block '/app/.env.production'
  must_block '/home/u/.ssh/id_rsa'
  must_block '/app/certs/server.pem'
  must_block '/app/composer.lock'
  must_block '/app/package-lock.json'
  must_block '/app/.github/workflows/ci.yml'
  must_block '/app/database/migrations/2026_01_01_create_users.php'

  must_allow '/app/src/Service/Billing.php'
  must_allow '/app/composer.json'
  must_allow '/app/package.json'
  must_allow '/app/README.md'
  must_allow '/app/tests/BillingTest.php'
  must_allow '/app/config/app.php'
  must_allow '/app/.env.example.md'

  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

[ "${1:-}" = "--selftest" ] && { selftest; exit $?; }

input=$(cat)
path=$(printf '%s' "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$path" ] && exit 0

check_path "$path"
exit $?
