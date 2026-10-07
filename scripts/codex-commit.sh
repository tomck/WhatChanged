#!/usr/bin/env bash

set -euo pipefail

# Keep the repository entry point while delegating identity detection to the
# user-level tool. It reads Codex's own session record and fails with status 3
# when it cannot determine the model and effort with certainty.
commit_tool=${AI_TOOLS_COMMIT:-${HOME}/.ai-tools/ai-commit}

if [[ ! -x $commit_tool ]]; then
    echo "Codex attribution tool is unavailable: ${commit_tool}" >&2
    echo "Install ~/.ai-tools or set AI_TOOLS_COMMIT to its ai-commit executable." >&2
    exit 3
fi

exec "$commit_tool" "$@"
