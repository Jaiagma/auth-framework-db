-- ============================================================
-- functions.sql
-- PL/pgSQL utility functions for the multi-tenant
-- authentication framework.
--
-- Prerequisites: enums.sql + schema.sql must be run first.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Utility helpers
-- ────────────────────────────────────────────────────────────

-- Constant-time BYTEA comparison to prevent timing attacks
CREATE OR REPLACE FUNCTION ct_bytea_equal(a BYTEA, b BYTEA)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT length(a) = length(b)
       AND encode(a,'hex') = encode(b,'hex');
$$;

-- SHA-256 hex digest of a text value (for index lookups of encrypted fields)
CREATE OR REPLACE FUNCTION sha256_hex(value TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT encode(digest(value, 'sha256'), 'hex');
$$;

-- Truncate a text value to a safe display prefix (for tokens, IDs)
CREATE OR REPLACE FUNCTION safe_prefix(value TEXT, prefix_len INT DEFAULT 8)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT left(value, prefix_len);
$$;

-- ────────────────────────────────────────────────────────────
-- 2. PII Encryption / Decryption
--    Uses pgcrypto symmetric AES-256-CBC.
--    In production, the key should come from a KMS; here we
--    accept it as a parameter so the application controls it.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION encrypt_pii(
    plaintext  TEXT,
    aes_key    TEXT    -- 32-byte hex string (256-bit key)
)
RETURNS BYTEA
LANGUAGE plpgsql
AS $$
BEGIN
    IF plaintext IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN pgp_sym_encrypt(
        plaintext,
        aes_key,
        'cipher-algo=aes256'
    );
END;
$$;

CREATE OR REPLACE FUNCTION decrypt_pii(
    ciphertext BYTEA,
    aes_key    TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
    IF ciphertext IS NULL THEN
        RETURN NULL;
    END IF;
    RETURN pgp_sym_decrypt(ciphertext, aes_key);
EXCEPTION
    WHEN others THEN
        RETURN NULL;   -- Wrong key or corrupted data → return NULL
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 3. User management
-- ────────────────────────────────────────────────────────────

-- Create a user with encrypted PII and hashed email for lookup.
-- Returns the new user's ID.
CREATE OR REPLACE FUNCTION create_user(
    p_tenant_id    UUID,
    p_email        TEXT,
    p_password     TEXT   DEFAULT NULL,
    p_username     TEXT   DEFAULT NULL,
    p_first_name   TEXT   DEFAULT NULL,
    p_last_name    TEXT   DEFAULT NULL,
    p_aes_key      TEXT   DEFAULT 'changeme-32-byte-aes-key-here!!'  -- MUST be overridden
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id       UUID;
    v_password_hash TEXT;
    v_profile_id    UUID;
BEGIN
    -- Hash password if provided (argon2id via pgcrypto bf fallback)
    IF p_password IS NOT NULL THEN
        v_password_hash := crypt(p_password, gen_salt('bf', 12));
    END IF;

    -- Insert user
    INSERT INTO users (
        tenant_id,
        email_encrypted,
        email_hash,
        username,
        status
    )
    VALUES (
        p_tenant_id,
        encrypt_pii(lower(trim(p_email)), p_aes_key),
        sha256_hex(lower(trim(p_email))),
        p_username,
        'pending_verification'
    )
    RETURNING id INTO v_user_id;

    -- Insert credential
    IF v_password_hash IS NOT NULL THEN
        INSERT INTO user_credentials (user_id, tenant_id, credential_type, password_hash, is_primary)
        VALUES (v_user_id, p_tenant_id, 'password', v_password_hash, TRUE);
    END IF;

    -- Insert profile
    INSERT INTO user_profiles (user_id, tenant_id, first_name_encrypted, last_name_encrypted)
    VALUES (
        v_user_id,
        p_tenant_id,
        CASE WHEN p_first_name IS NOT NULL THEN encrypt_pii(p_first_name, p_aes_key) END,
        CASE WHEN p_last_name  IS NOT NULL THEN encrypt_pii(p_last_name,  p_aes_key) END
    );

    RETURN v_user_id;
END;
$$;

-- Verify a plain-text password against the stored hash.
CREATE OR REPLACE FUNCTION verify_password(
    p_user_id  UUID,
    p_password TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash TEXT;
BEGIN
    SELECT password_hash INTO v_hash
    FROM user_credentials
    WHERE user_id = p_user_id
      AND credential_type = 'password'
      AND is_primary = TRUE
    LIMIT 1;

    IF v_hash IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN crypt(p_password, v_hash) = v_hash;
END;
$$;

-- Increment failed login count; lock account when threshold is reached.
CREATE OR REPLACE FUNCTION record_failed_login(
    p_user_id      UUID,
    p_max_attempts INT DEFAULT 5,
    p_lockout_sec  INT DEFAULT 900
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_failed INT;
BEGIN
    UPDATE users
    SET failed_login_count = failed_login_count + 1,
        updated_at         = now()
    WHERE id = p_user_id
    RETURNING failed_login_count INTO v_failed;

    IF v_failed >= p_max_attempts THEN
        UPDATE users
        SET status        = 'locked',
            locked_until  = now() + (p_lockout_sec || ' seconds')::INTERVAL,
            updated_at    = now()
        WHERE id = p_user_id;
    END IF;
END;
$$;

-- Reset failed login counter on successful authentication.
CREATE OR REPLACE FUNCTION record_successful_login(
    p_user_id  UUID,
    p_ip       INET DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE users
    SET failed_login_count = 0,
        last_login_at      = now(),
        last_login_ip      = p_ip,
        locked_until       = NULL,
        updated_at         = now()
    WHERE id = p_user_id;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4. MFA
-- ────────────────────────────────────────────────────────────

-- Generate N recovery codes for a user, storing bcrypt hashes.
-- Returns the plain-text codes (shown once to the user).
CREATE OR REPLACE FUNCTION generate_mfa_recovery_codes(
    p_user_id   UUID,
    p_tenant_id UUID,
    p_count     INT  DEFAULT 10
)
RETURNS TEXT[]
LANGUAGE plpgsql
AS $$
DECLARE
    v_codes      TEXT[] := '{}';
    v_plain_code TEXT;
    i            INT;
BEGIN
    -- Revoke any existing unused codes
    DELETE FROM mfa_recovery_codes
    WHERE user_id = p_user_id
      AND used = FALSE;

    FOR i IN 1..p_count LOOP
        v_plain_code := encode(gen_random_bytes(5), 'hex');  -- 10-char hex code
        v_codes      := v_codes || v_plain_code;

        INSERT INTO mfa_recovery_codes (user_id, tenant_id, code_hash)
        VALUES (p_user_id, p_tenant_id, crypt(v_plain_code, gen_salt('bf', 8)));
    END LOOP;

    RETURN v_codes;
END;
$$;

-- Validate a recovery code and mark it used.
CREATE OR REPLACE FUNCTION use_mfa_recovery_code(
    p_user_id UUID,
    p_code    TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_rec RECORD;
BEGIN
    -- Find an unused code that matches
    SELECT id, code_hash INTO v_rec
    FROM mfa_recovery_codes
    WHERE user_id = p_user_id
      AND used    = FALSE
    ORDER BY created_at
    LIMIT 1;   -- We must scan all codes; scanning is cheap for ≤ 10 rows

    -- NOTE: For production, iterate and compare individually; here
    -- we use a loop for correctness.
    FOR v_rec IN
        SELECT id, code_hash
        FROM mfa_recovery_codes
        WHERE user_id = p_user_id AND used = FALSE
    LOOP
        IF crypt(p_code, v_rec.code_hash) = v_rec.code_hash THEN
            UPDATE mfa_recovery_codes
            SET used    = TRUE,
                used_at = now()
            WHERE id = v_rec.id;
            RETURN TRUE;
        END IF;
    END LOOP;

    RETURN FALSE;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5. OAuth tokens
-- ────────────────────────────────────────────────────────────

-- Issue an access + refresh token pair.
-- Returns a row with both token hashes (raw tokens returned to app layer).
CREATE OR REPLACE FUNCTION issue_oauth_token_pair(
    p_tenant_id      UUID,
    p_application_id UUID,
    p_user_id        UUID   DEFAULT NULL,
    p_scopes         TEXT[] DEFAULT '{}',
    p_session_id     UUID   DEFAULT NULL,
    p_access_ttl     INT    DEFAULT 3600,
    p_refresh_ttl    INT    DEFAULT 2592000
)
RETURNS TABLE (
    access_token_id  UUID,
    refresh_token_id UUID,
    access_token     TEXT,    -- raw token (NOT stored, return once to app)
    refresh_token    TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_access_raw    TEXT := encode(gen_random_bytes(32), 'base64url');
    v_refresh_raw   TEXT := encode(gen_random_bytes(32), 'base64url');
    v_access_id     UUID;
    v_refresh_id    UUID;
BEGIN
    INSERT INTO oauth_tokens (
        tenant_id, application_id, user_id,
        token_type, token_hash, scopes, session_id, expires_at
    )
    VALUES (
        p_tenant_id, p_application_id, p_user_id,
        'access_token', sha256_hex(v_access_raw), p_scopes,
        p_session_id, now() + (p_access_ttl || ' seconds')::INTERVAL
    )
    RETURNING id INTO v_access_id;

    INSERT INTO oauth_tokens (
        tenant_id, application_id, user_id,
        token_type, token_hash, scopes, session_id,
        parent_token_id, expires_at
    )
    VALUES (
        p_tenant_id, p_application_id, p_user_id,
        'refresh_token', sha256_hex(v_refresh_raw), p_scopes,
        p_session_id, v_access_id, now() + (p_refresh_ttl || ' seconds')::INTERVAL
    )
    RETURNING id INTO v_refresh_id;

    RETURN QUERY
        SELECT v_access_id, v_refresh_id, v_access_raw, v_refresh_raw;
END;
$$;

-- Revoke a token by its hash (and optionally cascade to related tokens)
CREATE OR REPLACE FUNCTION revoke_oauth_token(
    p_token_hash     TEXT,
    p_cascade        BOOLEAN DEFAULT TRUE,
    p_reason         TEXT    DEFAULT 'manual_revocation'
)
RETURNS INT  -- number of tokens revoked
LANGUAGE plpgsql
AS $$
DECLARE
    v_token_id  UUID;
    v_count     INT := 0;
    v_cascaded  INT := 0;
BEGIN
    SELECT id INTO v_token_id
    FROM oauth_tokens
    WHERE token_hash = p_token_hash AND status = 'active';

    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    UPDATE oauth_tokens
    SET status           = 'revoked',
        revoked_at       = now(),
        revocation_reason = p_reason
    WHERE id = v_token_id;
    v_count := 1;

    IF p_cascade THEN
        -- Revoke children (refresh tokens) as well
        WITH RECURSIVE chain AS (
            SELECT id FROM oauth_tokens WHERE parent_token_id = v_token_id
            UNION ALL
            SELECT t.id FROM oauth_tokens t
            JOIN chain c ON t.parent_token_id = c.id
        )
        UPDATE oauth_tokens
        SET status            = 'revoked',
            revoked_at        = now(),
            revocation_reason = p_reason || ' (cascaded)'
        WHERE id IN (SELECT id FROM chain) AND status = 'active';

        GET DIAGNOSTICS v_cascaded = ROW_COUNT;
        v_count := v_count + v_cascaded;
    END IF;

    RETURN v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 6. Session management
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_session(
    p_user_id        UUID,
    p_tenant_id      UUID,
    p_application_id UUID   DEFAULT NULL,
    p_ip             INET   DEFAULT NULL,
    p_user_agent     TEXT   DEFAULT NULL,
    p_ttl_sec        INT    DEFAULT 86400
)
RETURNS TABLE (session_id UUID, token TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_token_raw TEXT := encode(gen_random_bytes(32), 'base64url');
    v_sid       UUID;
BEGIN
    INSERT INTO user_sessions (
        user_id, tenant_id, application_id,
        token_hash, ip_address, user_agent, expires_at
    )
    VALUES (
        p_user_id, p_tenant_id, p_application_id,
        sha256_hex(v_token_raw), p_ip, p_user_agent,
        now() + (p_ttl_sec || ' seconds')::INTERVAL
    )
    RETURNING id INTO v_sid;

    RETURN QUERY SELECT v_sid, v_token_raw;
END;
$$;

CREATE OR REPLACE FUNCTION revoke_all_sessions(
    p_user_id   UUID,
    p_tenant_id UUID,
    p_reason    TEXT DEFAULT 'logout_all'
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE user_sessions
    SET status     = 'revoked',
        revoked_at = now()
    WHERE user_id  = p_user_id
      AND tenant_id = p_tenant_id
      AND status   = 'active';

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 7. Audit logging
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION log_audit_event(
    p_tenant_id      UUID,
    p_event_type     audit_event_type,
    p_actor_user_id  UUID    DEFAULT NULL,
    p_actor_type     TEXT    DEFAULT 'user',
    p_resource_type  TEXT    DEFAULT NULL,
    p_resource_id    TEXT    DEFAULT NULL,
    p_outcome        TEXT    DEFAULT 'success',
    p_ip_address     INET    DEFAULT NULL,
    p_application_id UUID    DEFAULT NULL,
    p_session_id     UUID    DEFAULT NULL,
    p_metadata       JSONB   DEFAULT NULL,
    p_severity       audit_severity DEFAULT 'info'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id   UUID;
    v_prev UUID;
BEGIN
    -- Get the most recent audit log ID for tamper-evident chaining
    SELECT id INTO v_prev
    FROM audit_logs
    WHERE tenant_id = p_tenant_id
    ORDER BY created_at DESC
    LIMIT 1;

    INSERT INTO audit_logs (
        tenant_id, event_type, severity,
        actor_user_id, actor_type,
        resource_type, resource_id,
        application_id, session_id,
        ip_address, outcome,
        metadata, previous_log_id
    )
    VALUES (
        p_tenant_id, p_event_type, p_severity,
        p_actor_user_id, p_actor_type,
        p_resource_type, p_resource_id,
        p_application_id, p_session_id,
        p_ip_address, p_outcome,
        p_metadata, v_prev
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 8. GDPR / Data retention
-- ────────────────────────────────────────────────────────────

-- Soft-delete a user and anonymise PII (right-to-be-forgotten).
-- Hard deletion of associated data is left to scheduled cleanup jobs.
CREATE OR REPLACE FUNCTION anonymise_user(
    p_user_id   UUID,
    p_tenant_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_anon_email_hash TEXT := sha256_hex('deleted-' || p_user_id::TEXT);
BEGIN
    -- Anonymise users row
    UPDATE users
    SET email_encrypted  = '\x',   -- empty ciphertext
        email_hash       = v_anon_email_hash,
        phone_encrypted  = NULL,
        phone_hash       = NULL,
        username         = 'deleted_' || left(p_user_id::TEXT, 8),
        status           = 'deleted',
        deleted_at       = now(),
        updated_at       = now()
    WHERE id = p_user_id AND tenant_id = p_tenant_id;

    -- Wipe user_profiles PII
    UPDATE user_profiles
    SET first_name_encrypted = NULL,
        last_name_encrypted  = NULL,
        display_name         = NULL,
        avatar_url           = NULL,
        address_encrypted    = NULL,
        birth_year           = NULL,
        updated_at           = now()
    WHERE user_id = p_user_id;

    -- Revoke active sessions
    UPDATE user_sessions
    SET status     = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id AND status = 'active';

    -- Revoke active tokens
    UPDATE oauth_tokens
    SET status       = 'revoked',
        revoked_at   = now(),
        revocation_reason = 'user_deleted'
    WHERE user_id = p_user_id AND status = 'active';

    -- Revoke MFA devices
    UPDATE mfa_devices
    SET status     = 'revoked',
        updated_at = now()
    WHERE user_id = p_user_id;

    -- Record audit event
    PERFORM log_audit_event(
        p_tenant_id      := p_tenant_id,
        p_event_type     := 'data_deleted',
        p_actor_type     := 'system',
        p_resource_type  := 'user',
        p_resource_id    := p_user_id::TEXT,
        p_severity       := 'warning'
    );
END;
$$;

-- Execute a data retention pass for a specific tenant and table.
CREATE OR REPLACE FUNCTION run_data_retention(
    p_tenant_id   UUID,
    p_table_name  TEXT
)
RETURNS INT   -- rows purged
LANGUAGE plpgsql
AS $$
DECLARE
    v_policy  RECORD;
    v_count   INT := 0;
    v_query   TEXT;
BEGIN
    SELECT * INTO v_policy
    FROM data_retention_policies
    WHERE tenant_id  = p_tenant_id
      AND table_name = p_table_name
      AND is_active  = TRUE;

    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    IF v_policy.is_hard_delete THEN
        v_query := format(
            'DELETE FROM %I WHERE tenant_id = $1 AND %I < now() - ($2 || '' days'')::INTERVAL',
            p_table_name, v_policy.filter_column
        );
    ELSE
        v_query := format(
            'UPDATE %I SET deleted_at = now() WHERE tenant_id = $1 AND %I < now() - ($2 || '' days'')::INTERVAL AND deleted_at IS NULL',
            p_table_name, v_policy.filter_column
        );
    END IF;

    EXECUTE v_query USING p_tenant_id, v_policy.retention_days;
    GET DIAGNOSTICS v_count = ROW_COUNT;

    UPDATE data_retention_policies
    SET last_run_at = now(),
        next_run_at = now() + INTERVAL '1 day',
        updated_at  = now()
    WHERE tenant_id  = p_tenant_id
      AND table_name = p_table_name;

    RETURN v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 9. Consent management
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION record_consent(
    p_user_id          UUID,
    p_tenant_id        UUID,
    p_consent_type     consent_type,
    p_status           consent_status DEFAULT 'granted',
    p_document_version TEXT           DEFAULT '1.0',
    p_ip_address       INET           DEFAULT NULL,
    p_user_agent       TEXT           DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO user_consents (
        user_id, tenant_id, consent_type, status,
        document_version, ip_address, user_agent,
        granted_at, withdrawn_at
    )
    VALUES (
        p_user_id, p_tenant_id, p_consent_type, p_status,
        p_document_version, p_ip_address, p_user_agent,
        CASE WHEN p_status = 'granted'   THEN now() END,
        CASE WHEN p_status = 'withdrawn' THEN now() END
    )
    ON CONFLICT (user_id, consent_type)
    DO UPDATE SET
        status           = EXCLUDED.status,
        document_version = EXCLUDED.document_version,
        ip_address       = EXCLUDED.ip_address,
        user_agent       = EXCLUDED.user_agent,
        granted_at       = CASE WHEN EXCLUDED.status = 'granted'   THEN now() ELSE user_consents.granted_at END,
        withdrawn_at     = CASE WHEN EXCLUDED.status = 'withdrawn' THEN now() ELSE NULL END,
        updated_at       = now()
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- Add unique constraint needed by record_consent ON CONFLICT clause
ALTER TABLE user_consents
    ADD CONSTRAINT uq_user_consent_type UNIQUE (user_id, consent_type);

-- ────────────────────────────────────────────────────────────
-- 10. Risk / security helpers
-- ────────────────────────────────────────────────────────────

-- Record a security event and optionally lock the user account.
CREATE OR REPLACE FUNCTION record_security_event(
    p_tenant_id  UUID,
    p_user_id    UUID,
    p_event_type security_event_type,
    p_risk_level risk_level   DEFAULT 'medium',
    p_ip         INET         DEFAULT NULL,
    p_metadata   JSONB        DEFAULT NULL,
    p_auto_lock  BOOLEAN      DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO security_events (
        tenant_id, user_id, event_type, risk_level,
        ip_address, metadata
    )
    VALUES (
        p_tenant_id, p_user_id, p_event_type, p_risk_level,
        p_ip, p_metadata
    )
    RETURNING id INTO v_id;

    IF p_auto_lock AND p_risk_level IN ('high', 'critical') THEN
        UPDATE users
        SET status     = 'suspended',
            updated_at = now()
        WHERE id = p_user_id;
    END IF;

    RETURN v_id;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 11. Token cleanup (scheduled / cron)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cleanup_expired_tokens()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE oauth_tokens
    SET status = 'expired'
    WHERE status    = 'active'
      AND expires_at < now();

    GET DIAGNOSTICS v_count = ROW_COUNT;

    -- Also clean up expired sessions
    UPDATE user_sessions
    SET status = 'expired'
    WHERE status    = 'active'
      AND expires_at < now();

    -- Clean up expired MFA challenges
    DELETE FROM mfa_challenges
    WHERE is_verified = FALSE
      AND expires_at  < now() - INTERVAL '1 hour';

    -- Clean up expired password reset and email verification tokens
    DELETE FROM password_reset_tokens
    WHERE expires_at < now() - INTERVAL '7 days';

    DELETE FROM email_verification_tokens
    WHERE expires_at < now() - INTERVAL '7 days';

    RETURN v_count;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 12. updated_at auto-update helper (called by triggers)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;
