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

# The detector is optional. When it is missing, codex-commit.sh falls back to
# scripts/ai-commit.sh: it refuses to commit without supplied values rather
# than inventing a model, and records exactly the values it is given.
fallback_repo=${test_dir}/fallback-repo
git init -q "$fallback_repo"
git -C "$fallback_repo" config core.hooksPath .githooks
mkdir "${fallback_repo}/.githooks"
cp "$hook" "${fallback_repo}/.githooks/prepare-commit-msg"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid

if (cd "$fallback_repo" && AI_TOOLS_COMMIT="${test_dir}/missing" \
        "${repo_root}/scripts/codex-commit.sh" -- --allow-empty --no-gpg-sign -m x >/dev/null 2>&1); then
    echo "codex-commit.sh committed without a detector and without supplied values" >&2
    exit 1
fi
if git -C "$fallback_repo" rev-parse --verify -q HEAD >/dev/null; then
    echo "codex-commit.sh created a commit with no attribution values" >&2
    exit 1
fi

# Agent and model without an effort level must also be refused.
if (cd "$fallback_repo" && AI_TOOLS_COMMIT="${test_dir}/missing" \
        "${repo_root}/scripts/codex-commit.sh" --agent Codex --model gpt-test-model \
        -- --allow-empty --no-gpg-sign -m x >/dev/null 2>&1); then
    echo "codex-commit.sh committed without a reasoning effort" >&2
    exit 1
fi
if git -C "$fallback_repo" rev-parse --verify -q HEAD >/dev/null; then
    echo "codex-commit.sh created a commit with no reasoning effort" >&2
    exit 1
fi

# A stand-in codex binary supplies the version, as the real one would.
mkdir "${test_dir}/bin"
printf '#!/bin/sh\necho "codex-cli 9.9.9"\n' >"${test_dir}/bin/codex"
chmod +x "${test_dir}/bin/codex"

(cd "$fallback_repo" && PATH="${test_dir}/bin:${PATH}" AI_TOOLS_COMMIT="${test_dir}/missing" \
    "${repo_root}/scripts/codex-commit.sh" --agent Codex --model gpt-test-model --effort high \
    -- --allow-empty --no-gpg-sign -m 'Supplied identity' >/dev/null 2>&1)
fallback_message=$(git -C "$fallback_repo" log -1 --format=%B)
grep -Fqx 'Assisted-by: Codex:gpt-test-model' <<<"$fallback_message"
grep -Fqx 'Reasoning-Effort: high' <<<"$fallback_message"
grep -Fqx 'Agent-Version: codex-cli 9.9.9' <<<"$fallback_message"
if grep -Fq 'Agent-Thread:' <<<"$fallback_message"; then
    echo "codex-commit.sh fallback recorded a thread id nobody asked for" >&2
    exit 1
fi

# A version the caller supplied wins over the locally discovered one.
(cd "$fallback_repo" && PATH="${test_dir}/bin:${PATH}" AI_TOOLS_COMMIT="${test_dir}/missing" \
    "${repo_root}/scripts/codex-commit.sh" --agent Codex --model gpt-test-model --effort high \
    --agent-version 'codex-cli 1.2.3' \
    -- --allow-empty --no-gpg-sign -m 'Supplied version' >/dev/null 2>&1)
supplied_message=$(git -C "$fallback_repo" log -1 --format=%B)
grep -Fqx 'Agent-Version: codex-cli 1.2.3' <<<"$supplied_message"
[[ $(grep -Fc 'Agent-Version:' <<<"$supplied_message") == 1 ]]

# The older project-integrated wrapper also refuses to run without a model.
if "${repo_root}/scripts/claude-commit.sh" -- -m x 2>/dev/null; then
    echo "claude-commit.sh accepted a missing model" >&2
    exit 1
fi

# The shared wrapper now needs an effort level, so the Claude entry point does too.
before_count=$(git -C "$fallback_repo" rev-list --count HEAD)
if (cd "$fallback_repo" && "${repo_root}/scripts/claude-commit.sh" --model claude-test-model \
        -- --allow-empty --no-gpg-sign -m x >/dev/null 2>&1); then
    echo "claude-commit.sh accepted a missing reasoning effort" >&2
    exit 1
fi
[[ $(git -C "$fallback_repo" rev-list --count HEAD) == "$before_count" ]]

printf 'Git attribution hook tests passed.\n'
