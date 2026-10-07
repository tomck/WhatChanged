#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
hook=${repo_root}/.githooks/prepare-commit-msg
message_file=$(mktemp "${TMPDIR:-/tmp}/whatchanged-commit-message.XXXXXX")
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/whatchanged-commit-wrapper.XXXXXX")
trap 'rm -f "$message_file"; rm -rf "$test_dir"' EXIT

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

# The Codex repository wrapper delegates to the universal session detector and
# forwards the Git arguments without manufacturing identity values.
cat >"${test_dir}/ai-commit" <<'EOT'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${AI_COMMIT_TEST_LOG:?}"
EOT
chmod +x "${test_dir}/ai-commit"
AI_TOOLS_COMMIT="${test_dir}/ai-commit" \
AI_COMMIT_TEST_LOG="${test_dir}/arguments" \
    "${repo_root}/scripts/codex-commit.sh" -- -m 'Detected identity'
printf '%s\n' -- -m 'Detected identity' >"${test_dir}/expected"
cmp "${test_dir}/expected" "${test_dir}/arguments"

# A missing universal detector fails closed with the detector's uncertainty
# status instead of falling back to a hard-coded or environment model name.
set +e
AI_TOOLS_COMMIT="${test_dir}/missing" \
    "${repo_root}/scripts/codex-commit.sh" -- -m x >/dev/null 2>&1
codex_status=$?
set -e
if [[ $codex_status != 3 ]]; then
    echo "codex-commit.sh did not fail closed when its detector was unavailable" >&2
    exit 1
fi

# The older project-integrated wrapper also refuses to run without a model.
if "${repo_root}/scripts/claude-commit.sh" -- -m x 2>/dev/null; then
    echo "claude-commit.sh accepted a missing model" >&2
    exit 1
fi

printf 'Git attribution hook tests passed.\n'
