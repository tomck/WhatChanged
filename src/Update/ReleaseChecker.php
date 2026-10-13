<?php

namespace FreePBX\modules\Pendingchanges\Update;

class ReleaseChecker
{
    const INSTALLER_URL = 'https://tomck.github.io/WhatChanged/install.sh';
    const RELEASES_URL = 'https://github.com/tomck/WhatChanged/releases';
    const AUTOMATIC_CONFIG_KEY = 'automatic_release_checks';
    const CACHE_CONFIG_KEY = 'release_check_cache';
    const SUCCESS_TTL = 21600;
    const FAILURE_TTL = 900;
    const MAX_RESPONSE_BYTES = 65536;

    private $module;
    private $moduleRoot;
    private $fetcher;
    private $clock;

    public function __construct($module, $moduleRoot, $fetcher = null, $clock = null)
    {
        $this->module = $module;
        $this->moduleRoot = rtrim($moduleRoot, '/');
        $this->fetcher = $fetcher;
        $this->clock = $clock;
    }

    public function automaticEnabled()
    {
        $configured = $this->module->readModuleConfig(self::AUTOMATIC_CONFIG_KEY);
        if ($configured === null || $configured === false || $configured === '') {
            return true;
        }

        return (string) $configured === '1';
    }

    public function setAutomaticEnabled($enabled)
    {
        $this->module->writeModuleConfig(
            self::AUTOMATIC_CONFIG_KEY,
            $enabled ? '1' : '0'
        );
    }

    public function status($force = false)
    {
        $installedVersion = $this->installedVersion();
        $automatic = $this->automaticEnabled();
        $cache = $this->readCache();
        $now = $this->now();

        if (!$force && $this->cacheIsFresh($cache, $now)) {
            return $this->resultFromCache($cache, $installedVersion, $automatic, false);
        }

        if (!$force && !$automatic) {
            if ($cache !== null) {
                return $this->resultFromCache($cache, $installedVersion, false, true);
            }

            return $this->baseResult('disabled', $installedVersion, null, false, null, true);
        }

        $body = $this->fetchInstaller();
        $availableVersion = self::parseInstallerVersion($body);
        if ($availableVersion === null) {
            $cache = array(
                'state' => 'unavailable',
                'checked_at' => $now,
                'available_version' => null,
            );
            $this->writeCache($cache);

            return $this->resultFromCache($cache, $installedVersion, $automatic, false);
        }

        $cache = array(
            'state' => 'available',
            'checked_at' => $now,
            'available_version' => $availableVersion,
        );
        $this->writeCache($cache);

        return $this->resultFromCache($cache, $installedVersion, $automatic, false);
    }

    public static function parseInstallerVersion($body)
    {
        if (!is_string($body) || $body === '') {
            return null;
        }

        $matched = preg_match(
            '/^[ \t]*module_version=\$\{WHAT_CHANGED_VERSION:-([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\}[ \t]*$/m',
            $body,
            $matches
        );
        if ($matched !== 1) {
            return null;
        }

        return $matches[1];
    }

    private function resultFromCache(array $cache, $installedVersion, $automatic, $stale)
    {
        $checkedAt = isset($cache['checked_at']) ? (int) $cache['checked_at'] : null;
        $availableVersion = isset($cache['available_version'])
            ? $cache['available_version']
            : null;

        if ($stale) {
            return $this->baseResult(
                'disabled',
                $installedVersion,
                $availableVersion,
                false,
                $checkedAt,
                true
            );
        }

        if (!isset($cache['state']) || $cache['state'] !== 'available') {
            return $this->baseResult(
                'unavailable',
                $installedVersion,
                null,
                $automatic,
                $checkedAt,
                false
            );
        }

        if ($installedVersion === null) {
            return $this->baseResult(
                'unavailable',
                null,
                $availableVersion,
                $automatic,
                $checkedAt,
                false
            );
        }

        $comparison = version_compare($availableVersion, $installedVersion);
        if ($comparison > 0) {
            $state = 'update_available';
        } elseif ($comparison < 0) {
            $state = 'ahead';
        } else {
            $state = 'current';
        }

        return $this->baseResult(
            $state,
            $installedVersion,
            $availableVersion,
            $automatic,
            $checkedAt,
            false
        );
    }

    private function baseResult(
        $state,
        $installedVersion,
        $availableVersion,
        $automatic,
        $checkedAt,
        $stale
    ) {
        return array(
            'state' => $state,
            'installed_version' => $installedVersion,
            'available_version' => $availableVersion,
            'automatic' => (bool) $automatic,
            'checked_at' => $checkedAt,
            'stale' => (bool) $stale,
            'installer_url' => self::INSTALLER_URL,
            'releases_url' => self::RELEASES_URL,
        );
    }

    private function installedVersion()
    {
        $moduleXml = @file_get_contents($this->moduleRoot . '/module.xml');
        if (!is_string($moduleXml)) {
            return null;
        }

        if (
            preg_match(
                '/<version>\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*<\/version>/',
                $moduleXml,
                $matches
            ) !== 1
        ) {
            return null;
        }

        return $matches[1];
    }

    private function readCache()
    {
        $encoded = $this->module->readModuleConfig(self::CACHE_CONFIG_KEY);
        if (!is_string($encoded) || $encoded === '') {
            return null;
        }

        $decoded = json_decode($encoded, true);
        if (!is_array($decoded) || !isset($decoded['checked_at'])) {
            return null;
        }

        if (
            isset($decoded['available_version'])
            && $decoded['available_version'] !== null
            && preg_match('/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/', $decoded['available_version']) !== 1
        ) {
            return null;
        }

        return $decoded;
    }

    private function writeCache(array $cache)
    {
        $encoded = json_encode($cache);
        if (is_string($encoded)) {
            $this->module->writeModuleConfig(self::CACHE_CONFIG_KEY, $encoded);
        }
    }

    private function cacheIsFresh($cache, $now)
    {
        if (!is_array($cache) || !isset($cache['checked_at'])) {
            return false;
        }

        $ttl = isset($cache['state']) && $cache['state'] === 'available'
            ? self::SUCCESS_TTL
            : self::FAILURE_TTL;

        return (int) $cache['checked_at'] + $ttl > $now;
    }

    private function now()
    {
        if (is_callable($this->clock)) {
            return (int) call_user_func($this->clock);
        }

        return time();
    }

    private function fetchInstaller()
    {
        if (is_callable($this->fetcher)) {
            return call_user_func($this->fetcher, self::INSTALLER_URL);
        }

        if (function_exists('curl_init')) {
            return $this->fetchWithCurl();
        }

        return $this->fetchWithStreams();
    }

    private function fetchWithCurl()
    {
        $handle = curl_init(self::INSTALLER_URL);
        if ($handle === false) {
            return null;
        }

        $body = '';
        $tooLarge = false;
        curl_setopt($handle, CURLOPT_FOLLOWLOCATION, false);
        curl_setopt($handle, CURLOPT_CONNECTTIMEOUT, 2);
        curl_setopt($handle, CURLOPT_TIMEOUT, 4);
        curl_setopt($handle, CURLOPT_SSL_VERIFYPEER, true);
        curl_setopt($handle, CURLOPT_SSL_VERIFYHOST, 2);
        curl_setopt($handle, CURLOPT_USERAGENT, 'WhatChanged release checker');
        if (defined('CURLOPT_PROTOCOLS') && defined('CURLPROTO_HTTPS')) {
            curl_setopt($handle, CURLOPT_PROTOCOLS, CURLPROTO_HTTPS);
        }
        curl_setopt(
            $handle,
            CURLOPT_WRITEFUNCTION,
            function ($unused, $chunk) use (&$body, &$tooLarge) {
                if (strlen($body) + strlen($chunk) > self::MAX_RESPONSE_BYTES) {
                    $tooLarge = true;
                    return 0;
                }
                $body .= $chunk;
                return strlen($chunk);
            }
        );

        $successful = curl_exec($handle);
        $status = (int) curl_getinfo($handle, CURLINFO_HTTP_CODE);
        if (PHP_VERSION_ID < 80500) {
            curl_close($handle);
        }

        if ($successful === false || $tooLarge || $status !== 200) {
            return null;
        }

        return $body;
    }

    private function fetchWithStreams()
    {
        $context = stream_context_create(
            array(
                'http' => array(
                    'method' => 'GET',
                    'timeout' => 4,
                    'follow_location' => 0,
                    'header' => "User-Agent: WhatChanged release checker\r\nConnection: close\r\n",
                ),
                'ssl' => array(
                    'verify_peer' => true,
                    'verify_peer_name' => true,
                ),
            )
        );
        $body = @file_get_contents(
            self::INSTALLER_URL,
            false,
            $context,
            0,
            self::MAX_RESPONSE_BYTES + 1
        );
        if (!is_string($body) || strlen($body) > self::MAX_RESPONSE_BYTES) {
            return null;
        }

        return $body;
    }
}
