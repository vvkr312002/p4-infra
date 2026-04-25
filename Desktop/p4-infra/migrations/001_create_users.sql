-- Migration 001: Create users table
-- Run once on fresh DB: mysql -h <RDS_ENDPOINT> -u admin -p securechat < 001_create_users.sql

CREATE TABLE IF NOT EXISTS users (
    id            CHAR(36)        NOT NULL DEFAULT (UUID()),
    username      VARCHAR(64)     NOT NULL,
    password_hash VARCHAR(255)    NOT NULL,   -- bcrypt hash, never plaintext
    public_key    TEXT            NOT NULL,   -- RSA-OAEP 2048 public key, base64-encoded
    role          ENUM('user','admin') NOT NULL DEFAULT 'user',
    created_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    UNIQUE KEY uq_username (username)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
