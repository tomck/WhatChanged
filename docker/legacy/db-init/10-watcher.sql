CREATE USER IF NOT EXISTS 'what_changed'@'%' IDENTIFIED BY 'legacy-watcher-only';
GRANT SELECT ON `asterisk`.* TO 'what_changed'@'%';
FLUSH PRIVILEGES;
