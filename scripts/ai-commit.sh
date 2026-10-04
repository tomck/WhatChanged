#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOT'
Usage:
  scripts/ai-commit.sh --agent AGENT --model MODEL [--effort EFFORT]
                       [--agent-version VERSION] [--thread ID]
                       -- GIT_COMMIT_ARGUMENTS...

Adds Assisted-by: AGENT:MODEL (plus Agent-Version, Reasoning-Effort and
Agent-Thread when supplied) through the repository's prepare-commit-msg hook.
Prefer scripts/claude-commit.sh or scripts/codex-commit.sh for those agents.
EOT
}

agent=${AI_COMMIT_AGENT:-}
model=${AI_COMMIT_MODEL:-}
effort=${AI_COMMIT_EFFORT:-}
agent_version=${AI_COMMIT_AGENT_VERSION:-}
thread=${AI_COMMIT_THREAD:-}

need_value() {
    (($# >= 2)) || { echo "$1 requires a value" >&2; exit 2; }
}

while (($#)); do
    case $1 in
        --agent) need_value "$@"; agent=$2; shift 2 ;;
        --model) need_value "$@"; model=$2; shift 2 ;;
        --effort|--reasoning-effort) need_value "$@"; effort=$2; shift 2 ;;
        --agent-version) need_value "$@"; agent_version=$2; shift 2 ;;
        --thread) need_value "$@"; thread=$2; shift 2 ;;
        --agent=*) agent=${1#*=}; shift ;;
        --model=*) model=${1#*=}; shift ;;
        --effort=*|--reasoning-effort=*) effort=${1#*=}; shift ;;
        --agent-version=*) agent_version=${1#*=}; shift ;;
        --thread=*) thread=${1#*=}; shift ;;
        --) shift; break ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown wrapper option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z $agent || -z $model ]]; then
    echo "Both --agent and a precise --model are required; refusing to guess attribution." >&2
    exit 2
fi

if (($# == 0)); then
    echo "Pass git commit arguments after --." >&2
    usage >&2
    exit 2
fi

hooks_path=$(git config --get core.hooksPath || true)
if [[ $hooks_path != .githooks ]]; then
    echo "Attribution hook is not active; run scripts/install-git-hooks.sh first." >&2
    exit 2
fi

export AI_COMMIT=1
export AI_COMMIT_AGENT=$agent
export AI_COMMIT_MODEL=$model
export AI_COMMIT_EFFORT=$effort
export AI_COMMIT_AGENT_VERSION=$agent_version
export AI_COMMIT_THREAD=$thread

exec git commit "$@"
