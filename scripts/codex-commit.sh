#!/usr/bin/env bash

set -euo pipefail

# Optional convenience: when the user-level ai-commit detector is installed it
# reads Codex's own session record, so nobody types a model or effort by hand.
# It is not part of this repository and nobody has to install it. Without it,
# fall back to scripts/ai-commit.sh, which needs --agent, --model and --effort
# supplied by the user, and add the locally discoverable Codex version unless
# the caller gave --agent-version. An installed detector that cannot decide
# exits with status 3 and is never bypassed.
commit_tool=${AI_TOOLS_COMMIT:-${HOME}/.ai-tools/ai-commit}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [[ -x $commit_tool ]]; then
    exec "$commit_tool" "$@"
fi

echo "Optional ai-commit detector not found (${commit_tool}); using scripts/ai-commit.sh." >&2
echo "Pass the exact values the user gave you: --agent Codex --model MODEL --effort LEVEL." >&2

have_version=0
for arg in "$@"; do
    [[ $arg == -- ]] && break
    [[ $arg == --agent-version || $arg == --agent-version=* ]] && have_version=1
done

extra=()
if ((have_version == 0)) && [[ -z ${AI_COMMIT_AGENT_VERSION:-} ]] && command -v codex >/dev/null 2>&1; then
    detected=$(codex --version 2>/dev/null | head -n 1 || true)
    [[ -n $detected ]] && extra=(--agent-version "$detected")
fi

exec "${script_dir}/ai-commit.sh" ${extra[@]+"${extra[@]}"} "$@"
