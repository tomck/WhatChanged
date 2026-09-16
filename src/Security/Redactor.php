<?php

namespace FreePBX\modules\Pendingchanges\Security;

use FreePBX\modules\Pendingchanges\Support\PathResolver;

class Redactor
{
    const PROTECTED_VALUE_PREFIX = '[protected hmac-sha256:';

    private $paths;
    private $redactionKeyCache;

    public function __construct(PathResolver $paths)
    {
        $this->paths = $paths;
    }

    public static function semanticNameSensitive($value)
    {
        $pattern = '/(^|[_.|\/\s\-])'
            . '(password|passwd|secret|token|value_digest|pin|credential|private_key|api_key|apikey|auth_key|authkey)'
            . '($|[_.|\/\s\-])/i';

        return preg_match(
            $pattern,
            (string) $value
        ) === 1;
    }

    public static function sensitiveField($field, array $row)
    {
        $name = strtolower((string) $field);
        $pattern = '/password|passwd|secret|token|value_digest|pin|credential|'
            . 'private_key|api_key|apikey|auth_key|authkey/i';
        if (preg_match($pattern, $name)) {
            return true;
        }

        if (substr($name, -4) === '_key' || strpos($name, 'key_') === 0) {
            return true;
        }

        if (in_array($name, array('value', 'val', 'data'), true)) {
            $semantic = array();
            foreach (array('module', 'keyword', 'key', 'variable', 'setting', 'option', 'name') as $semanticField) {
                $semantic[] = isset($row[$semanticField]) ? $row[$semanticField] : '';
            }

            return self::semanticNameSensitive(implode(' ', $semantic));
        }

        return false;
    }

    public function protectRow(array $row)
    {
        foreach ($row as $field => $value) {
            if (!self::sensitiveField($field, $row)) {
                continue;
            }
            if (is_string($value) && strpos($value, self::PROTECTED_VALUE_PREFIX) === 0) {
                continue;
            }

            $serialized = json_encode($value, JSON_UNESCAPED_SLASHES);
            $row[$field] = self::PROTECTED_VALUE_PREFIX
                . hash_hmac(
                    'sha256',
                    $serialized === false ? (string) $value : $serialized,
                    $this->redactionKey()
                ) . ']';
        }

        return $row;
    }

    public function publicRow(array $row)
    {
        foreach ($row as $field => $value) {
            if (
                self::sensitiveField($field, $row)
                || (is_string($value) && strpos($value, self::PROTECTED_VALUE_PREFIX) !== false)
            ) {
                $row[$field] = '[redacted]';
            }
        }

        return $row;
    }

    private function redactionKey()
    {
        if (is_string($this->redactionKeyCache) && strlen($this->redactionKeyCache) >= 32) {
            return $this->redactionKeyCache;
        }

        $path = $this->paths->asteriskVariableRoot() . '/pendingchanges-redaction.key';
        $encoded = @file_get_contents($path);
        if (is_string($encoded) && preg_match('/^[a-f0-9]{64}$/', trim($encoded))) {
            $this->redactionKeyCache = pack('H*', trim($encoded));

            return $this->redactionKeyCache;
        }

        if (function_exists('random_bytes')) {
            $key = random_bytes(32);
        } elseif (function_exists('openssl_random_pseudo_bytes')) {
            $key = openssl_random_pseudo_bytes(32);
        } else {
            throw new \RuntimeException('No secure random source is available for fallback redaction.');
        }

        if (!is_string($key) || strlen($key) < 32) {
            throw new \RuntimeException('Could not generate the fallback redaction key.');
        }

        $handle = @fopen($path, 'x');
        if ($handle !== false) {
            fwrite($handle, bin2hex($key));
            fclose($handle);
            @chmod($path, 0600);
        } else {
            $encoded = @file_get_contents($path);
            if (!is_string($encoded) || !preg_match('/^[a-f0-9]{64}$/', trim($encoded))) {
                throw new \RuntimeException('Could not create the fallback redaction key.');
            }
            $key = pack('H*', trim($encoded));
        }

        $this->redactionKeyCache = $key;

        return $key;
    }
}
