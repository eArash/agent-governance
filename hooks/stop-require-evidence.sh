#!/usr/bin/env bash
# Stop hook. Refuses to let a turn end on a completion claim that no command supports.
#
# This is the enforcement of rule 1: "nothing is done until a command prints the evidence."
# An agent will write "tests pass" because the sentence is the natural end of the paragraph
# it is composing, not because it ran anything. The claim is cheap; only the command is not.
#
# Input : the session transcript path as JSON on stdin (Claude Code passes .transcript_path)
# Output: exit 0 to allow the turn to end, exit 2 with a reason to block it
#
# Self-test: ./stop-require-evidence.sh --selftest
set -uo pipefail

# Words that assert a verified state. Deliberately narrow: "I fixed the typo" is not a claim
# about a system, "tests pass" is. Over-broad matching here would block every turn and get the
# hook disabled, which is worse than not having it (failures/README.md #2).
CLAIM_RE='(tests? (pass|are green|all green)|all tests? (pass|green)|suite is green|build (succeed|passes)|migration ran|deployed successfully|verified working|confirmed working)'

# Evidence that a command actually ran in this turn.
EVIDENCE_RE='(tool_use|"name"[[:space:]]*:[[:space:]]*"Bash"|OK \([0-9]|Tests:[[:space:]]*[0-9]|[0-9]+ (passed|passing)|exit(ed)? (code )?[0-9])'

check_turn() {
  local text="$1"
  printf '%s' "$text" | grep -Eqi -- "$CLAIM_RE" || return 0          # no claim, nothing to check
  printf '%s' "$text" | grep -Eq  -- "$EVIDENCE_RE" && return 0        # claim + evidence, fine
  printf 'BLOCKED: this turn claims a verified state without a command having produced it.\n' >&2
  printf 'Run the thing you are claiming and let its output stand as the evidence.\n' >&2
  return 2
}

selftest() {
  local fail=0 pass=0
  must_block() { if check_turn "$1" 2>/dev/null; then printf '  MISS   %s\n' "${1:0:60}"; fail=$((fail+1)); else pass=$((pass+1)); fi; }
  must_allow() { if check_turn "$1" 2>/dev/null; then pass=$((pass+1)); else printf '  FALSE+ %s\n' "${1:0:60}"; fail=$((fail+1)); fi; }

  must_block 'I refactored the service and the tests pass.'
  must_block 'All tests green, ready to merge.'
  must_block 'The migration ran and everything looks correct.'
  must_block 'Deployed successfully to staging.'

  must_allow 'I refactored the service. {"name":"Bash"} OK (412 tests, 990 assertions)'
  must_allow 'Tests: 4323, Failures: 0 — so the suite is green.'
  must_allow 'I renamed the variable and updated the two call sites.'
  must_allow 'This needs a decision from you before I continue.'
  must_allow 'exit code 0 — build succeeded'

  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
  [ "$fail" -eq 0 ]
}

[ "${1:-}" = "--selftest" ] && { selftest; exit $?; }

input=$(cat)
transcript=$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -z "$transcript" ] || [ ! -f "$transcript" ] && exit 0   # never block on a missing transcript

# Only the tail matters: the claim, if there is one, is in what was just written.
check_turn "$(tail -c 20000 "$transcript" 2>/dev/null)"
exit $?
