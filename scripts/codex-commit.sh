#!/usr/bin/env bash

set -euo pipefail

# Compatibility wrapper for Codex; see scripts/ai-commit.sh. Accepts the same
# options as before (--model, --reasoning-effort, --thread) or the
# CODEX_COMMIT_* environment variables.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
extra=()
[[ -n ${CODEX_COMMIT_MODEL:-} ]] && extra+=(--model "$CODEX_COMMIT_MODEL")
[[ -n ${CODEX_COMMIT_REASONING_EFFORT:-} ]] && extra+=(--effort "$CODEX_COMMIT_REASONING_EFFORT")
[[ -n ${CODEX_COMMIT_THREAD_ID:-} ]] && extra+=(--thread "$CODEX_COMMIT_THREAD_ID")

exec "$here/ai-commit.sh" --agent Codex ${extra[@]+"${extra[@]}"} "$@"
