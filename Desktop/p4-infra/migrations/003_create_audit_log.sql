-- Migration 003: Create audit_log table
-- Depends on: 001_create_users.sql
-- Captures every auth event (register, login, login_fail, logout, pubkey_fetch).

CREATE TABLE IF NOT EXISTS audit_log (
    id         BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id    CHAR(36)        NULL,           -- NULL for failed logins (unknown user)
    event      VARCHAR(64)     NOT NULL,       -- 'register' | 'login' | 'login_fail' | 'logout' | 'pubkey_fetch'
    ip         VARCHAR(45)     NOT NULL,       -- IPv4 or IPv6
    user_agent VARCHAR(512)    NULL,           -- optional browser/client info
    metadata   JSON            NULL,           -- extra context (e.g. failure reason)
    created_at DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX idx_user_id   (user_id, created_at),
    INDEX idx_event     (event, created_at),
    INDEX idx_ip        (ip, created_at),

    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
