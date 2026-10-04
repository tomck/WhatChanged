#!/usr/bin/env bash

set -euo pipefail

# Claude Code commits:
#   scripts/claude-commit.sh --model claude-sonnet-5-5 --effort high -- -m "Message"
# The Claude Code version is detected from `claude --version` when available.

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
have_version=0
for arg in "$@"; do
    [[ $arg == -- ]] && break
    [[ $arg == --agent-version || $arg == --agent-version=* ]] && have_version=1
done

extra=()
if ((have_version == 0)) && command -v claude >/dev/null 2>&1; then
    detected=$(claude --version 2>/dev/null | head -n 1 || true)
    [[ -n $detected ]] && extra=(--agent-version "$detected")
fi

exec "$here/ai-commit.sh" --agent Claude ${extra[@]+"${extra[@]}"} "$@"
