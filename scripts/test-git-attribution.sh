#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
hook=${repo_root}/.githooks/prepare-commit-msg
message_file=$(mktemp "${TMPDIR:-/tmp}/whatchanged-commit-message.XXXXXX")
trap 'rm -f "$message_file"' EXIT

printf 'Test commit\n' >"$message_file"
"$hook" "$message_file"
if [[ $(cat "$message_file") != "Test commit" ]]; then
    echo "Inactive hook changed a human commit message" >&2
    exit 1
fi

# Legacy Codex environment still produces an Assisted-by trailer.
CODEX_COMMIT=1 \
CODEX_COMMIT_MODEL=gpt-test-model \
CODEX_COMMIT_REASONING_EFFORT=high \
CODEX_COMMIT_THREAD_ID=test-thread \
    "$hook" "$message_file"

grep -Fqx 'Assisted-by: Codex:gpt-test-model' "$message_file"
grep -Fqx 'Reasoning-Effort: high' "$message_file"
grep -Fqx 'Agent-Thread: test-thread' "$message_file"

# A second run replaces, never duplicates, attribution.
AI_COMMIT=1 \
AI_COMMIT_AGENT=Claude \
AI_COMMIT_MODEL=claude-test-model \
AI_COMMIT_EFFORT=medium \
AI_COMMIT_AGENT_VERSION='Claude Code 0.0.0' \
    "$hook" "$message_file"

[[ $(grep -Fc 'Assisted-by:' "$message_file") == 1 ]]
grep -Fqx 'Assisted-by: Claude:claude-test-model' "$message_file"
grep -Fqx 'Agent-Version: Claude Code 0.0.0' "$message_file"
grep -Fqx 'Reasoning-Effort: medium' "$message_file"
if grep -Fq 'gpt-test-model' "$message_file"; then
    echo "Hook retained stale model attribution" >&2
    exit 1
fi

# An active gate with no model must fail rather than guess.
printf 'Another commit\n' >"$message_file"
if AI_COMMIT=1 AI_COMMIT_AGENT=Claude "$hook" "$message_file" 2>/dev/null; then
    echo "Hook accepted a missing model" >&2
    exit 1
fi

# The wrappers refuse to run without a model.
if "${repo_root}/scripts/claude-commit.sh" -- -m x 2>/dev/null; then
    echo "claude-commit.sh accepted a missing model" >&2
    exit 1
fi

printf 'Git attribution hook tests passed.\n'
