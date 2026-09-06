#!/usr/bin/env bash
# PostToolUse hook for Bash. Appends every command to a log. Blocks nothing, ever.
#
# Why: after an incident, the question is always "what did it actually run?" — and the answer
# has to exist before you need it. This is the cheapest guard in the repository and the one that
# has repaid itself most often.
#
# The log is append-only by convention and rotated by size, not by date: a rotation keyed to a
# calendar boundary loses the busiest hour of an incident, which is exactly the hour you want.
set -uo pipefail

LOG_DIR="${AGENT_GOVERNANCE_LOG_DIR:-${CLAUDE_PROJECT_DIR:-.}/.agent-audit}"
LOG="$LOG_DIR/bash-commands.jsonl"
MAX_BYTES="${AGENT_GOVERNANCE_LOG_MAX:-5242880}"   # 5 MB

mkdir -p "$LOG_DIR" 2>/dev/null || exit 0          # never fail the turn over logging

if [ -f "$LOG" ]; then
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  [ "$size" -gt "$MAX_BYTES" ] && mv "$LOG" "$LOG.$(date +%s).old" 2>/dev/null
fi

input=$(cat)
command=$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)"[[:space:]]*[,}].*/\1/p' | head -1)
[ -z "$command" ] && exit 0

# One JSON object per line. Written with printf %s so a command containing quotes cannot
# break the record — the command field is stored base64 for exactly that reason.
printf '{"ts":"%s","cwd":"%s","b64":"%s"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "$(pwd)" \
  "$(printf '%s' "$command" | base64 | tr -d '\n')" >> "$LOG" 2>/dev/null

exit 0
