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

CODEX_COMMIT=1 \
CODEX_COMMIT_MODEL=gpt-test-model \
CODEX_COMMIT_REASONING_EFFORT=high \
CODEX_COMMIT_THREAD_ID=test-thread \
    "$hook" "$message_file"

grep -Fqx 'Co-authored-by: Codex <noreply@openai.com>' "$message_file"
grep -Fqx 'Codex-Model: gpt-test-model' "$message_file"
grep -Fqx 'Codex-Reasoning-Effort: high' "$message_file"
grep -Fqx 'Codex-Thread: test-thread' "$message_file"

CODEX_COMMIT=1 \
CODEX_COMMIT_MODEL=gpt-second-model \
CODEX_COMMIT_REASONING_EFFORT=medium \
    "$hook" "$message_file"

[[ $(grep -Fxc 'Co-authored-by: Codex <noreply@openai.com>' "$message_file") == 1 ]]
grep -Fqx 'Codex-Model: gpt-second-model' "$message_file"
grep -Fqx 'Codex-Reasoning-Effort: medium' "$message_file"
if grep -Fq 'Codex-Model: gpt-test-model' "$message_file"; then
    echo "Hook retained stale model attribution" >&2
    exit 1
fi

printf 'Git attribution hook tests passed.\n'
