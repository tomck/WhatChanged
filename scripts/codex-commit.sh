#!/usr/bin/env bash

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  scripts/codex-commit.sh --model MODEL [--reasoning-effort EFFORT]
                          [--thread THREAD_ID] -- GIT_COMMIT_ARGUMENTS...

Examples:
  scripts/codex-commit.sh --model gpt-6-astra --reasoning-effort high -- \
      -m "Improve watcher diagnostics"

  scripts/codex-commit.sh --model gpt-5.6-sol --reasoning-effort ultra \
      --thread "$CODEX_THREAD_ID" -- -am "Refine release gate"

The wrapper enables the repository's gated prepare-commit-msg hook. Normal
`git commit` commands are not attributed to Codex.
EOF
}

model=${CODEX_COMMIT_MODEL:-}
reasoning=${CODEX_COMMIT_REASONING_EFFORT:-}
thread=${CODEX_COMMIT_THREAD_ID:-}

while (($#)); do
    case $1 in
        --model)
            (($# >= 2)) || { echo "--model requires a value" >&2; exit 2; }
            model=$2
            shift 2
            ;;
        --model=*)
            model=${1#*=}
            shift
            ;;
        --reasoning-effort)
            (($# >= 2)) || { echo "--reasoning-effort requires a value" >&2; exit 2; }
            reasoning=$2
            shift 2
            ;;
        --reasoning-effort=*)
            reasoning=${1#*=}
            shift
            ;;
        --thread)
            (($# >= 2)) || { echo "--thread requires a value" >&2; exit 2; }
            thread=$2
            shift 2
            ;;
        --thread=*)
            thread=${1#*=}
            shift
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown wrapper option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ -z $model ]]; then
    echo "A precise --model value is required; refusing to guess attribution." >&2
    exit 2
fi

if (($# == 0)); then
    echo "Pass git commit arguments after --." >&2
    usage >&2
    exit 2
fi

export CODEX_COMMIT=1
export CODEX_COMMIT_MODEL=$model
export CODEX_COMMIT_REASONING_EFFORT=$reasoning
export CODEX_COMMIT_THREAD_ID=$thread

exec git commit "$@"
