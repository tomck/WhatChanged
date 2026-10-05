#!/bin/sh
# Shared lifecycle helpers for the optional web-PHP attribution sensor.
# Callers must use `set -e`: validation or reload failures intentionally stop
# uninstall before the PHP sensor library is deleted.

what_changed_systemd_active() {
  command -v systemctl >/dev/null 2>&1 \
    && systemctl is-active --quiet "$1" >/dev/null 2>&1
}

what_changed_process_active() {
  command -v pgrep >/dev/null 2>&1 && pgrep -x "$1" >/dev/null 2>&1
}

what_changed_remove_sensor_configuration() {
  apache_active=0
  if what_changed_systemd_active apache2.service \
      || what_changed_systemd_active httpd.service \
      || what_changed_process_active apache2 \
      || what_changed_process_active httpd; then
    apache_active=1
  fi

  nginx_active=0
  if what_changed_systemd_active nginx.service \
      || what_changed_process_active nginx; then
    nginx_active=1
  fi

  fpm_versions=
  for fpm_directory in /etc/php/*/fpm; do
    [ -d "$fpm_directory" ] || continue
    version=$(basename "$(dirname "$fpm_directory")")
    if what_changed_systemd_active "php${version}-fpm.service" \
        || [ -s "/run/php/php${version}-fpm.pid" ] \
        || what_changed_process_active "php-fpm${version}"; then
      fpm_versions="$fpm_versions $version"
    fi
  done

  rhel_fpm_active=0
  if [ -d /etc/php.d ] \
      && { what_changed_systemd_active php-fpm.service \
        || what_changed_process_active php-fpm; }; then
    rhel_fpm_active=1
  fi

  for sensor in /etc/php/*/apache2/conf.d/99-what-changed-attribution.ini \
      /etc/php/*/fpm/conf.d/99-what-changed-attribution.ini \
      /etc/php.d/99-what-changed-attribution.ini; do
    [ ! -f "$sensor" ] || rm -f "$sensor"
  done

  # Validate every active web stack after removing the ini but before the
  # referenced PHP library is deleted. If validation or reload fails, the
  # caller exits with the library still present and can repair the stack.
  if [ "$apache_active" -eq 1 ]; then
    echo 'Validating Apache after removing the WhatChanged request sensor.'
    apachectl configtest || return $?
  fi
  if [ "$nginx_active" -eq 1 ]; then
    echo 'Validating nginx after removing the WhatChanged request sensor.'
    nginx -t || return $?
  fi
  for version in $fpm_versions; do
    if command -v "php-fpm$version" >/dev/null 2>&1; then
      echo "Validating PHP $version FPM after removing the WhatChanged request sensor."
      "php-fpm$version" -t || return $?
    fi
  done
  if [ "$rhel_fpm_active" -eq 1 ] && command -v php-fpm >/dev/null 2>&1; then
    echo 'Validating PHP-FPM after removing the WhatChanged request sensor.'
    php-fpm -t || return $?
  fi

  if [ "$apache_active" -eq 1 ]; then
    if what_changed_systemd_active apache2.service; then
      systemctl reload apache2 || return $?
    elif what_changed_systemd_active httpd.service; then
      systemctl reload httpd || return $?
    else
      apachectl -k graceful || return $?
    fi
  fi
  for version in $fpm_versions; do
    if what_changed_systemd_active "php${version}-fpm.service"; then
      systemctl reload "php${version}-fpm.service" || return $?
    elif [ -s "/run/php/php${version}-fpm.pid" ]; then
      kill -USR2 "$(cat "/run/php/php${version}-fpm.pid")" || return $?
    fi
  done
  if [ "$rhel_fpm_active" -eq 1 ]; then
    if what_changed_systemd_active php-fpm.service; then
      systemctl reload php-fpm.service || return $?
    elif [ -s /run/php-fpm/php-fpm.pid ]; then
      kill -USR2 "$(cat /run/php-fpm/php-fpm.pid)" || return $?
    fi
  fi
  if [ "$nginx_active" -eq 1 ]; then
    if what_changed_systemd_active nginx.service; then
      systemctl reload nginx.service || return $?
    else
      nginx -s reload || return $?
    fi
  fi
}
