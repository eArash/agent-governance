#!/usr/bin/env bash
# Install the governance hooks into a project, then prove every guard can fail.
#
# usage: ./install.sh /path/to/your/project
#
# It does not overwrite an existing settings.json — it prints the fragment for you to merge,
# because silently rewriting a config file is the kind of thing this repository exists to stop.
set -uo pipefail

TARGET="${1:-}"
[ -z "$TARGET" ] && { echo "usage: $0 /path/to/your/project" >&2; exit 1; }
[ -d "$TARGET" ] || { echo "not a directory: $TARGET" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$TARGET/.claude/hooks"

echo "── 1. exercising every guard before installing anything"
failed=0
for h in "$HERE"/hooks/*.sh; do
  if grep -q -- '--selftest' "$h"; then
    bash "$h" --selftest || failed=1
  else
    printf '%s: no self-test (audit-only hook)\n' "$(basename "$h")"
  fi
done
[ "$failed" -ne 0 ] && { echo "a guard failed its own self-test — nothing installed" >&2; exit 2; }

echo
echo "── 2. copying hooks to $DEST"
mkdir -p "$DEST"
cp "$HERE"/hooks/*.sh "$DEST"/
chmod +x "$DEST"/*.sh
ls -1 "$DEST"

echo
echo "── 3. copying the doctrine to $TARGET/.claude/rules"
mkdir -p "$TARGET/.claude/rules"
cp "$HERE"/rules/*.md "$TARGET/.claude/rules/" 2>/dev/null && ls -1 "$TARGET/.claude/rules"

echo
echo "── 4. add this to $TARGET/.claude/settings.json (merge by hand — I will not rewrite it)"
cat "$HERE/settings.example.json"

echo
echo "Done. Read .claude/rules/verification.md first; it is short and does most of the work."
