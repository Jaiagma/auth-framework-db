-- =============================================================================
-- functions.sql
-- PL/pgSQL functions for the multi-tenant authentication framework.
-- Includes UUID v7 generation, PII encryption/decryption, audit helpers,
-- session management, cleanup jobs, and utility functions.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- UUID v7 generator
-- UUID v7 embeds a 48-bit millisecond Unix timestamp in the most-significant
-- bits, giving sortable identifiers with excellent B-tree locality.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS UUID
LANGUAGE plpgsql
PARALLEL SAFE
AS $$
DECLARE
    v_time        BIGINT;
    v_unix_ms     BIGINT;
    v_rand        BYTEA;
    v_hex         TEXT;
BEGIN
    -- Milliseconds since Unix epoch
    v_unix_ms := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;

    -- 12 random bytes (96 bits)
    v_rand := gen_random_bytes(10);

    -- Build 128-bit UUID v7:
    -- Bits 0-47   : unix_ts_ms (48 bits)
    -- Bits 48-51  : version = 0x7 (4 bits)
    -- Bits 52-63  : rand_a   (12 bits)
    -- Bits 64-65  : variant  = 0b10 (2 bits)
    -- Bits 66-127 : rand_b   (62 bits)
    v_hex :=
        lpad(to_hex(v_unix_ms), 12, '0') ||          -- 48-bit timestamp (12 hex chars)
        '7' ||                                         -- version nibble
        lpad(to_hex((get_byte(v_rand, 0) & 15)), 1, '0') ||  -- 4 bits rand_a
        lpad(to_hex(get_byte(v_rand, 1)), 2, '0') ||  -- 8 bits rand_a cont.
        lpad(to_hex((get_byte(v_rand, 2) & 63) | 128), 2, '0') || -- variant + 6 bits
        encode(substring(v_rand from 4 for 6), 'hex'); -- 48 bits rand_b

    -- Pad to 32 hex chars and format as UUID
    v_hex := lpad(v_hex, 32, '0');

    RETURN (
        substring(v_hex, 1, 8)  || '-' ||
        substring(v_hex, 9, 4)  || '-' ||
        substring(v_hex, 13, 4) || '-' ||
        substring(v_hex, 17, 4) || '-' ||
        substring(v_hex, 21, 12)
    )::UUID;
END;
$$;

COMMENT ON FUNCTION uuid_generate_v7() IS
    'Generates a UUID v7 with embedded millisecond timestamp for sorted inserts.';

-- ---------------------------------------------------------------------------
-- Timestamp extraction from UUID v7
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION uuid_v7_to_timestamptz(p_uuid UUID)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT to_timestamp(
        ('x' || lpad(replace(p_uuid::TEXT, '-', ''), 12, '0'))::BIT(48)::BIGINT / 1000.0
    );
$$;

COMMENT ON FUNCTION uuid_v7_to_timestamptz(UUID) IS
    'Extracts the creation timestamp embedded in a UUID v7 value.';

-- ---------------------------------------------------------------------------
-- updated_at trigger helper
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- PII Encryption / Decryption
-- Uses pgcrypto symmetric encryption with a per-tenant key derived from a
-- master secret stored in an environment variable / secrets manager.
-- In production replace 'MASTER_SECRET_REPLACE_ME' with a call to a
-- secrets manager (e.g., AWS Secrets Manager, HashiCorp Vault).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION encrypt_pii(p_plaintext TEXT, p_tenant_id UUID)
RETURNS BYTEA
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key TEXT;
BEGIN
    IF p_plaintext IS NULL THEN
        RETURN NULL;
    END IF;
    -- Derive a per-tenant encryption key (HMAC-SHA256 of tenant id + master secret)
    v_key := encode(
        hmac(p_tenant_id::TEXT, current_setting('app.pii_master_key', TRUE), 'sha256'),
        'hex'
    );
    RETURN pgp_sym_encrypt(p_plaintext, v_key);
END;
$$;

CREATE OR REPLACE FUNCTION decrypt_pii(p_ciphertext BYTEA, p_tenant_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_key TEXT;
BEGIN
    IF p_ciphertext IS NULL THEN
        RETURN NULL;
    END IF;
    v_key := encode(
        hmac(p_tenant_id::TEXT, current_setting('app.pii_master_key', TRUE), 'sha256'),
        'hex'
    );
    RETURN pgp_sym_decrypt(p_ciphertext, v_key);
END;
$$;

COMMENT ON FUNCTION encrypt_pii(TEXT, UUID) IS
    'Encrypts a plaintext PII value using a per-tenant AES key.';
COMMENT ON FUNCTION decrypt_pii(BYTEA, UUID) IS
    'Decrypts a PII ciphertext using the per-tenant AES key.';

-- ---------------------------------------------------------------------------
-- HMAC hash helper (for PII lookup fields like email_hash)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hmac_sha256(p_value TEXT, p_tenant_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
    RETURN encode(
        hmac(
            p_value,
            current_setting('app.pii_master_key', TRUE) || p_tenant_id::TEXT,
            'sha256'
        ),
        'hex'
    );
END;
$$;

-- ---------------------------------------------------------------------------
-- Audit log writer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_write_audit_log(
    p_tenant_id       UUID,
    p_user_id         UUID,
    p_actor_id        UUID,
    p_application_id  UUID,
    p_session_id      UUID,
    p_action          audit_action,
    p_resource_type   TEXT,
    p_resource_id     UUID     DEFAULT NULL,
    p_ip_address      INET     DEFAULT NULL,
    p_user_agent      TEXT     DEFAULT NULL,
    p_old_values      JSONB    DEFAULT NULL,
    p_new_values      JSONB    DEFAULT NULL,
    p_metadata        JSONB    DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO audit_logs (
        id, tenant_id, user_id, actor_id, application_id, session_id,
        action, resource_type, resource_id,
        ip_address, user_agent, old_values, new_values, metadata
    ) VALUES (
        uuid_generate_v7(), p_tenant_id, p_user_id, p_actor_id,
        p_application_id, p_session_id, p_action, p_resource_type,
        p_resource_id, p_ip_address, p_user_agent,
        p_old_values, p_new_values, COALESCE(p_metadata, '{}')
    )
    RETURNING id INTO v_id;

    RETURN v_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Session validation
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_session(
    p_session_token_hash  TEXT,
    p_tenant_id           UUID
)
RETURNS TABLE (
    session_id      UUID,
    user_id         UUID,
    application_id  UUID,
    is_valid        BOOLEAN,
    failure_reason  TEXT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.id,
        s.user_id,
        s.application_id,
        CASE
            WHEN s.id IS NULL                   THEN FALSE
            WHEN s.status <> 'active'           THEN FALSE
            WHEN s.expires_at < now()           THEN FALSE
            WHEN u.status <> 'active'           THEN FALSE
            ELSE TRUE
        END AS is_valid,
        CASE
            WHEN s.id IS NULL                   THEN 'session_not_found'
            WHEN s.status = 'revoked'           THEN 'session_revoked'
            WHEN s.status = 'expired'           THEN 'session_expired'
            WHEN s.status = 'logged_out'        THEN 'session_logged_out'
            WHEN s.expires_at < now()           THEN 'session_expired'
            WHEN u.status = 'locked'            THEN 'user_locked'
            WHEN u.status = 'suspended'         THEN 'user_suspended'
            WHEN u.status = 'deleted'           THEN 'user_deleted'
            ELSE NULL
        END AS failure_reason
    FROM sessions s
    JOIN users u ON u.id = s.user_id
    WHERE s.session_token_hash = p_session_token_hash
      AND s.tenant_id = p_tenant_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Lock user account (after too many failed login attempts)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_record_failed_login(
    p_user_id           UUID,
    p_max_attempts      INT     DEFAULT 10,
    p_lockout_minutes   INT     DEFAULT 30
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_attempts INT;
BEGIN
    UPDATE users
    SET failed_login_attempts = failed_login_attempts + 1,
        updated_at = now()
    WHERE id = p_user_id
    RETURNING failed_login_attempts INTO v_attempts;

    IF v_attempts >= p_max_attempts THEN
        UPDATE users
        SET status       = 'locked',
            locked_until = now() + (p_lockout_minutes || ' minutes')::INTERVAL,
            updated_at   = now()
        WHERE id = p_user_id;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- Reset failed login counter on successful auth
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_reset_failed_logins(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE users
    SET failed_login_attempts = 0,
        locked_until          = NULL,
        status                = CASE WHEN status = 'locked' THEN 'active' ELSE status END,
        last_login_at         = now(),
        updated_at            = now()
    WHERE id = p_user_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Data retention cleanup
-- Deletes / anonymizes records according to data_retention_policies
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_run_retention_cleanup(p_tenant_id UUID DEFAULT NULL)
RETURNS TABLE (resource_type TEXT, rows_processed BIGINT)
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
    v_cutoff TIMESTAMPTZ;
    v_rows   BIGINT;
BEGIN
    FOR rec IN
        SELECT drp.*
        FROM data_retention_policies drp
        WHERE drp.is_active = TRUE
          AND (p_tenant_id IS NULL OR drp.tenant_id = p_tenant_id)
    LOOP
        v_cutoff := now() - (rec.retention_days || ' days')::INTERVAL;

        IF rec.action = 'delete' THEN
            CASE rec.resource_type
                WHEN 'audit_logs' THEN
                    DELETE FROM audit_logs
                    WHERE tenant_id = rec.tenant_id
                      AND occurred_at < v_cutoff;
                    GET DIAGNOSTICS v_rows = ROW_COUNT;
                WHEN 'sessions' THEN
                    DELETE FROM sessions
                    WHERE tenant_id = rec.tenant_id
                      AND created_at < v_cutoff
                      AND status IN ('expired','revoked','logged_out');
                    GET DIAGNOSTICS v_rows = ROW_COUNT;
                WHEN 'security_events' THEN
                    DELETE FROM security_events
                    WHERE tenant_id = rec.tenant_id
                      AND occurred_at < v_cutoff;
                    GET DIAGNOSTICS v_rows = ROW_COUNT;
                ELSE
                    v_rows := 0;
            END CASE;
        ELSIF rec.action = 'anonymize' THEN
            -- Anonymize users who requested deletion
            UPDATE users
            SET email_encrypted  = NULL,
                email_hash       = 'ANONYMIZED_' || id::TEXT,
                phone_encrypted  = NULL,
                phone_hash       = NULL,
                first_name_encrypted = NULL,
                last_name_encrypted  = NULL,
                display_name     = 'Deleted User',
                avatar_url       = NULL,
                status           = 'deleted',
                updated_at       = now()
            WHERE tenant_id = rec.tenant_id
              AND deleted_at IS NOT NULL
              AND deleted_at < v_cutoff;
            GET DIAGNOSTICS v_rows = ROW_COUNT;
        ELSE
            v_rows := 0;
        END IF;

        resource_type   := rec.resource_type;
        rows_processed  := v_rows;
        RETURN NEXT;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Revoke all sessions for a user (e.g., password change, account takeover)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_revoke_user_sessions(
    p_user_id   UUID,
    p_except_session UUID DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE sessions
    SET status     = 'revoked',
        revoked_at = now()
    WHERE user_id = p_user_id
      AND status  = 'active'
      AND (p_except_session IS NULL OR id <> p_except_session);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- ---------------------------------------------------------------------------
-- Get active MFA devices for a user
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_user_mfa_devices(p_user_id UUID)
RETURNS TABLE (
    device_id   UUID,
    method      mfa_method,
    name        TEXT,
    last_used_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
AS $$
    SELECT id, method, name, last_used_at
    FROM mfa_devices
    WHERE user_id = p_user_id
      AND status  = 'active'
    ORDER BY last_used_at DESC NULLS LAST;
$$;

-- ---------------------------------------------------------------------------
-- Check if a user has completed MFA enrollment
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_user_has_mfa(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM mfa_devices
        WHERE user_id = p_user_id AND status = 'active'
    );
$$;

-- ---------------------------------------------------------------------------
-- Generate n recovery codes (returns hashed codes; caller stores plaintext)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generate_recovery_codes(
    p_user_id   UUID,
    p_tenant_id UUID,
    p_count     INT DEFAULT 10
)
RETURNS TABLE (code TEXT, code_hash TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_code      TEXT;
    v_code_hash TEXT;
    i           INT;
BEGIN
    -- Invalidate old codes
    DELETE FROM mfa_recovery_codes
    WHERE user_id = p_user_id AND tenant_id = p_tenant_id;

    FOR i IN 1..p_count LOOP
        -- 8 random bytes -> 16 hex chars, formatted as XXXX-XXXX-XXXX-XXXX
        v_code := upper(
            substring(encode(gen_random_bytes(8), 'hex'), 1, 4) || '-' ||
            substring(encode(gen_random_bytes(8), 'hex'), 1, 4) || '-' ||
            substring(encode(gen_random_bytes(8), 'hex'), 1, 4) || '-' ||
            substring(encode(gen_random_bytes(8), 'hex'), 1, 4)
        );
        v_code_hash := encode(digest(v_code, 'sha256'), 'hex');

        INSERT INTO mfa_recovery_codes (id, user_id, tenant_id, code_hash)
        VALUES (uuid_generate_v7(), p_user_id, p_tenant_id, v_code_hash);

        code      := v_code;
        code_hash := v_code_hash;
        RETURN NEXT;
    END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Process PII deletion request
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_process_deletion_request(p_request_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    rec RECORD;
BEGIN
    SELECT * INTO rec
    FROM pii_deletion_requests
    WHERE id = p_request_id AND status = 'in_progress';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deletion request % not found or not in_progress', p_request_id;
    END IF;

    -- Revoke all sessions
    PERFORM fn_revoke_user_sessions(rec.user_id);

    -- Revoke OAuth tokens
    UPDATE oauth_tokens
    SET status = 'revoked', revoked_at = now()
    WHERE user_id = rec.user_id;

    -- Revoke API keys
    UPDATE api_keys
    SET status = 'revoked', revoked_at = now()
    WHERE tenant_id = rec.tenant_id
      AND created_by = rec.user_id;

    -- Anonymize user PII
    UPDATE users
    SET email_encrypted      = NULL,
        email_hash           = 'DELETED_' || rec.user_id::TEXT,
        phone_encrypted      = NULL,
        phone_hash           = NULL,
        first_name_encrypted = NULL,
        last_name_encrypted  = NULL,
        display_name         = 'Deleted User',
        avatar_url           = NULL,
        status               = 'deleted',
        deleted_at           = now(),
        updated_at           = now()
    WHERE id = rec.user_id;

    -- Mark request complete
    UPDATE pii_deletion_requests
    SET status       = 'completed',
        completed_at = now(),
        updated_at   = now()
    WHERE id = p_request_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Expire stale sessions (called by a scheduled job)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_expire_sessions()
RETURNS INT
LANGUAGE plpgsql
AS $$
DECLARE
    v_count INT;
BEGIN
    UPDATE sessions
    SET status = 'expired'
    WHERE status    = 'active'
      AND expires_at < now();

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;
