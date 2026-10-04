#!/usr/bin/env bash
# PreToolUse hook: block bare `git commit` from Claude Code so attribution
# always goes through scripts/claude-commit.sh.
cmd=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
case $cmd in
  *claude-commit.sh*|*ai-commit.sh*|*codex-commit.sh*) exit 0 ;;
esac
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-][^[:space:]]*[[:space:]]+)?)*commit([[:space:]]|$)'; then
  echo "Use scripts/claude-commit.sh --model <model-id> [--effort <level>] -- <git commit args> so the commit carries Assisted-by attribution (see CLAUDE.md)." >&2
  exit 2
fi
exit 0
