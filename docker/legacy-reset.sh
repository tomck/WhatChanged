#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
compose_file="$root_dir/docker/legacy/docker-compose.yml"
target=${1:-}

case "$target" in
  16)
    services=(fpbx16-watcher fpbx16 fpbx16-database)
    volumes=(fpbx16-attribution fpbx16-data fpbx16-database fpbx16-watcher-state fpbx16-web)
    ;;
  15)
    services=(fpbx15-watcher fpbx15)
    volumes=(fpbx15-asterisk-config fpbx15-asterisk-var fpbx15-attribution fpbx15-database fpbx15-watcher-state fpbx15-web)
    ;;
  14)
    services=(fpbx14-watcher fpbx14)
    volumes=(fpbx14-asterisk-config fpbx14-asterisk-var fpbx14-attribution fpbx14-database fpbx14-watcher-state fpbx14-web)
    ;;
  *)
    echo 'usage: docker/legacy-reset.sh 16|15|14' >&2
    exit 2
    ;;
esac

export PATH="/Applications/Docker.app/Contents/Resources/bin:$PATH"

# These names are fixed by the explicit Compose project name. Only the chosen
# disposable legacy fixture is removed; the main FreePBX 17 lab is untouched.
docker compose -f "$compose_file" --profile "$target" rm -s -f "${services[@]}"
for volume in "${volumes[@]}"; do
  full_name="whatchanged-legacy_$volume"
  if docker volume inspect "$full_name" >/dev/null 2>&1; then
    docker volume rm "$full_name" >/dev/null
  fi
done

echo "FreePBX $target disposable legacy fixture reset"
