#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd "$(dirname "$0")/.." && pwd)
source "$root_dir/deploy/release-versions.sh"

if [[ -z "$module_version" ]]; then
  echo 'module.xml does not contain a 17.x.y.z source version' >&2
  exit 1
fi

"$root_dir/scripts/package-legacy-test-releases.sh"

portable="$root_dir/dist/what-changed-watcher-portable_0.1.2.tar.gz"
portable_stage=$(mktemp -d)
trap 'rm -rf "$portable_stage"' EXIT
tar -xzf "$portable" -C "$portable_stage"
portable_root="$portable_stage/what-changed-watcher-portable-0.1.2"
test -x "$portable_root/install.sh"
test -x "$portable_root/uninstall.sh"
sh -n "$portable_root/install.sh" "$portable_root/uninstall.sh"
grep -q 'ExecStart=/usr/bin/python3 /usr/local/lib/what-changed-watcher/watcher.py' \
  "$portable_root/files/what-changed-watcher.service"
grep -q 'auto_prepend_file=/usr/local/lib/what-changed-watcher/what-changed-request-audit.php' \
  "$portable_root/files/99-what-changed-attribution.ini"
cmp "$portable_root/files/watcher.py" "$root_dir/docker/custom-watcher/watcher.py"

for specification in '14 5.6' '15 5.6' '16 7.4' '17 8.2'; do
  read -r target php_version <<<"$specification"
  archive="$root_dir/dist/pendingchanges-$module_version.tgz"
  if [[ "$target" == 17 ]]; then
    "$root_dir/scripts/package-module.sh" --target 17 --output-dir "$root_dir/dist" >/dev/null
  fi

  tar -tzf "$archive" | grep -qx 'pendingchanges/module.xml'
  tar -xOf "$archive" pendingchanges/module.xml | grep -q "<version>$module_version</version>"
  tar -xOf "$archive" pendingchanges/module.xml | grep -q "<version>$target.0</version>"
  for payload in bin/install-watcher bin/uninstall-watcher watcher/watcher.py \
    watcher/what-changed-request-audit.php watcher/99-what-changed-attribution.ini \
    watcher/what-changed-watcher.service watcher/what-changed-watcher.env \
    watcher/configure-database.php watcher/what-changed-watcher-configure \
    watcher/what-changed-watcher-install-sensor; do
    tar -tzf "$archive" | grep -qx "pendingchanges/$payload"
  done

  docker run --rm \
    -v "$archive:/tmp/pendingchanges.tgz:ro" \
    -v "$root_dir/docker/legacy-page-smoke.php:/tmp/legacy-page-smoke.php:ro" \
    -v "$root_dir/docker/watcher-health-smoke.php:/tmp/watcher-health-smoke.php:ro" \
    "php:$php_version-cli" sh -eu -c '
      work=$(mktemp -d)
      tar -xzf /tmp/pendingchanges.tgz -C "$work"
      find "$work/pendingchanges" -type f \( -name "*.php" -o -name "*.class.php" \) -print \
        | while IFS= read -r source; do php -l "$source" >/dev/null; done
      php /tmp/legacy-page-smoke.php "$work/pendingchanges"
      php /tmp/legacy-page-smoke.php "$work/pendingchanges" degraded
      php /tmp/watcher-health-smoke.php "$work/pendingchanges"
    '
  echo "FreePBX $target candidate passed PHP $php_version syntax and metadata checks"
done

for php_version in 5.6 7.4 8.2; do
  docker run --rm \
    -v "$root_dir/deploy/what-changed-request-audit.php:/deploy/what-changed-request-audit.php:ro" \
    -v "$root_dir/docker/test-request-audit.php:/tmp/test-request-audit.php:ro" \
    "php:$php_version-cli" php /tmp/test-request-audit.php /tmp/what-changed-audit-test.jsonl
done

docker run --rm \
  -v "$root_dir/docker/custom-watcher/watcher.py:/tmp/watcher.py:ro" \
  python:3.6-slim python -m py_compile /tmp/watcher.py

echo 'Legacy compatibility gate passed'
