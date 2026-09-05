#!/usr/bin/env bash

set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

configured=$(git config --local --get core.hooksPath || true)
if [[ -n $configured && $configured != .githooks ]]; then
    echo "Refusing to replace existing core.hooksPath: ${configured}" >&2
    exit 1
fi

git config --local core.hooksPath .githooks
echo "Configured core.hooksPath=.githooks for ${repo_root}"
