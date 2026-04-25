-- Migration 002: Create messages table
-- Depends on: 001_create_users.sql
-- NOTE: ciphertext, encrypted_key, and iv are ALWAYS ciphertext — never plaintext.

CREATE TABLE IF NOT EXISTS messages (
    id            CHAR(36)    NOT NULL DEFAULT (UUID()),
    from_user_id  CHAR(36)    NOT NULL,
    to_user_id    CHAR(36)    NOT NULL,

    -- AES-GCM encrypted message body (base64-encoded ciphertext)
    ciphertext    LONGTEXT    NOT NULL,

    -- RSA-OAEP wrapped AES key (base64-encoded), encrypted with recipient's public key
    encrypted_key TEXT        NOT NULL,

    -- AES-GCM initialisation vector (base64-encoded, 12 bytes)
    iv            VARCHAR(32) NOT NULL,

    -- Delivery state for offline queue support
    delivered     TINYINT(1)  NOT NULL DEFAULT 0,

    created_at    DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (id),
    INDEX idx_to_user   (to_user_id, delivered, created_at),
    INDEX idx_from_user (from_user_id, created_at),

    CONSTRAINT fk_msg_from FOREIGN KEY (from_user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_msg_to   FOREIGN KEY (to_user_id)   REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci;
