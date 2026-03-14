-- =============================================================================
-- triggers.sql
-- Triggers for the multi-tenant authentication framework.
-- Covers: updated_at timestamps, audit logging, password validation,
--         session expiry tracking, and security event generation.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- HELPER: attach updated_at trigger to a table
-- ---------------------------------------------------------------------------

-- Tenants
CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Applications
CREATE TRIGGER trg_applications_updated_at
    BEFORE UPDATE ON applications
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Users
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- MFA devices
CREATE TRIGGER trg_mfa_devices_updated_at
    BEFORE UPDATE ON mfa_devices
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Identity providers
CREATE TRIGGER trg_identity_providers_updated_at
    BEFORE UPDATE ON identity_providers
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- OIDC configurations
CREATE TRIGGER trg_oidc_configurations_updated_at
    BEFORE UPDATE ON oidc_configurations
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- SAML configurations
CREATE TRIGGER trg_saml_configurations_updated_at
    BEFORE UPDATE ON saml_configurations
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Federated identities
CREATE TRIGGER trg_federated_identities_updated_at
    BEFORE UPDATE ON federated_identities
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- User localization preferences
CREATE TRIGGER trg_user_localization_preferences_updated_at
    BEFORE UPDATE ON user_localization_preferences
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Tenant regional settings
CREATE TRIGGER trg_tenant_regional_settings_updated_at
    BEFORE UPDATE ON tenant_regional_settings
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- UI translations
CREATE TRIGGER trg_ui_translations_updated_at
    BEFORE UPDATE ON ui_translations
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- User consents
CREATE TRIGGER trg_user_consents_updated_at
    BEFORE UPDATE ON user_consents
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Data retention policies
CREATE TRIGGER trg_data_retention_policies_updated_at
    BEFORE UPDATE ON data_retention_policies
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- PII deletion requests
CREATE TRIGGER trg_pii_deletion_requests_updated_at
    BEFORE UPDATE ON pii_deletion_requests
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Data export requests
CREATE TRIGGER trg_data_export_requests_updated_at
    BEFORE UPDATE ON data_export_requests
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- Webhooks
CREATE TRIGGER trg_webhooks_updated_at
    BEFORE UPDATE ON webhooks
    FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ---------------------------------------------------------------------------
-- AUDIT: users table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_users()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_action audit_action;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_action := 'user_created';
        PERFORM fn_write_audit_log(
            NEW.tenant_id, NEW.id, NULL, NULL, NULL,
            v_action, 'users', NEW.id,
            NULL, NULL, NULL,
            jsonb_build_object('status', NEW.status, 'role', NEW.role)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        -- Status change
        IF OLD.status <> NEW.status THEN
            IF NEW.status = 'locked' THEN
                v_action := 'user_locked';
            ELSIF OLD.status = 'locked' AND NEW.status = 'active' THEN
                v_action := 'user_unlocked';
            ELSE
                v_action := 'user_updated';
            END IF;
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.id, NULL, NULL, NULL,
                v_action, 'users', NEW.id,
                NULL, NULL,
                jsonb_build_object('status', OLD.status),
                jsonb_build_object('status', NEW.status)
            );
        END IF;
        -- Soft delete
        IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.id, NULL, NULL, NULL,
                'user_deleted', 'users', NEW.id,
                NULL, NULL, NULL, NULL
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_users
    AFTER INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION fn_audit_users();

-- ---------------------------------------------------------------------------
-- AUDIT: sessions table
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_sessions()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_write_audit_log(
            NEW.tenant_id, NEW.user_id, NULL, NEW.application_id, NEW.id,
            'user_login', 'sessions', NEW.id,
            NEW.ip_address, NEW.user_agent, NULL,
            jsonb_build_object('method', NEW.auth_methods, 'mfa_verified', NEW.mfa_verified)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status = 'active' AND NEW.status = 'logged_out' THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NEW.application_id, NEW.id,
                'user_logout', 'sessions', NEW.id,
                NULL, NULL, NULL, NULL
            );
        ELSIF OLD.status = 'active' AND NEW.status = 'revoked' THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NEW.application_id, NEW.id,
                'user_logout', 'sessions', NEW.id,
                NULL, NULL, NULL,
                jsonb_build_object('reason', 'revoked')
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_sessions
    AFTER INSERT OR UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION fn_audit_sessions();

-- ---------------------------------------------------------------------------
-- AUDIT: MFA devices
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_mfa_devices()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'active' THEN
        PERFORM fn_write_audit_log(
            NEW.tenant_id, NEW.user_id, NULL, NULL, NULL,
            'mfa_enrolled', 'mfa_devices', NEW.id,
            NULL, NULL, NULL,
            jsonb_build_object('method', NEW.method)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status <> 'active' AND NEW.status = 'active' THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NULL, NULL,
                'mfa_enrolled', 'mfa_devices', NEW.id,
                NULL, NULL, NULL,
                jsonb_build_object('method', NEW.method)
            );
        ELSIF OLD.status = 'active' AND NEW.status IN ('disabled','revoked') THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NULL, NULL,
                'mfa_disabled', 'mfa_devices', NEW.id,
                NULL, NULL, NULL,
                jsonb_build_object('method', NEW.method)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_mfa_devices
    AFTER INSERT OR UPDATE ON mfa_devices
    FOR EACH ROW EXECUTE FUNCTION fn_audit_mfa_devices();

-- ---------------------------------------------------------------------------
-- AUDIT: OAuth tokens
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_oauth_tokens()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM fn_write_audit_log(
            NEW.tenant_id, NEW.user_id, NULL, NEW.application_id, NEW.session_id,
            'oauth_token_issued', 'oauth_tokens', NEW.id,
            NULL, NULL, NULL,
            jsonb_build_object('token_type', NEW.token_type, 'grant_type', NEW.grant_type)
        );
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status <> 'revoked' AND NEW.status = 'revoked' THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NEW.application_id, NEW.session_id,
                'oauth_token_revoked', 'oauth_tokens', NEW.id,
                NULL, NULL, NULL,
                jsonb_build_object('token_type', NEW.token_type)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_oauth_tokens
    AFTER INSERT OR UPDATE ON oauth_tokens
    FOR EACH ROW EXECUTE FUNCTION fn_audit_oauth_tokens();

-- ---------------------------------------------------------------------------
-- AUDIT: User consent changes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_user_consents()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
        IF NEW.status = 'given' AND (TG_OP = 'INSERT' OR OLD.status <> 'given') THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NULL, NULL,
                'consent_given', 'user_consents', NEW.id,
                NEW.ip_address, NULL, NULL,
                jsonb_build_object('consent_type', NEW.consent_type, 'version', NEW.version)
            );
        ELSIF NEW.status = 'withdrawn' AND (TG_OP = 'INSERT' OR OLD.status <> 'withdrawn') THEN
            PERFORM fn_write_audit_log(
                NEW.tenant_id, NEW.user_id, NULL, NULL, NULL,
                'consent_revoked', 'user_consents', NEW.id,
                NULL, NULL, NULL,
                jsonb_build_object('consent_type', NEW.consent_type, 'version', NEW.version)
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_audit_user_consents
    AFTER INSERT OR UPDATE ON user_consents
    FOR EACH ROW EXECUTE FUNCTION fn_audit_user_consents();

-- ---------------------------------------------------------------------------
-- SECURITY: auto-generate security event on repeated failed logins
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_detect_brute_force()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Threshold: 5 failures → medium, 10 → high, 20 → critical
    IF NEW.failed_login_attempts IN (5, 10, 20) THEN
        INSERT INTO security_events (
            id, tenant_id, user_id, event_type, severity,
            description, risk_score, occurred_at
        ) VALUES (
            uuid_generate_v7(),
            NEW.tenant_id,
            NEW.id,
            'brute_force',
            CASE NEW.failed_login_attempts
                WHEN 5  THEN 'medium'::security_event_severity
                WHEN 10 THEN 'high'::security_event_severity
                ELSE        'critical'::security_event_severity
            END,
            'Brute-force attempt detected: ' || NEW.failed_login_attempts || ' failed logins',
            LEAST(NEW.failed_login_attempts * 5, 100),
            now()
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_detect_brute_force
    AFTER UPDATE OF failed_login_attempts ON users
    FOR EACH ROW EXECUTE FUNCTION fn_detect_brute_force();

-- ---------------------------------------------------------------------------
-- SECURITY: auto-expire sessions past their expiry time on access
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auto_expire_session()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'active' AND NEW.expires_at < now() THEN
        NEW.status := 'expired';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_expire_session
    BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION fn_auto_expire_session();

-- ---------------------------------------------------------------------------
-- COMPLIANCE: set scheduled_for on new PII deletion requests
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_schedule_deletion_request()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Default: 30 days cool-off period (GDPR Art. 17 allows reasonable time)
    IF NEW.scheduled_for IS NULL THEN
        NEW.scheduled_for := now() + INTERVAL '30 days';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_schedule_deletion_request
    BEFORE INSERT ON pii_deletion_requests
    FOR EACH ROW EXECUTE FUNCTION fn_schedule_deletion_request();

-- ---------------------------------------------------------------------------
-- INTEGRITY: prevent password reuse (last 5 passwords)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_password_reuse()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_reused BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM user_passwords
        WHERE user_id = NEW.user_id
          AND is_current = FALSE
          AND password_hash = NEW.password_hash
        ORDER BY created_at DESC
        LIMIT 5
    ) INTO v_reused;

    IF v_reused THEN
        RAISE EXCEPTION 'Password has been used recently.' USING ERRCODE = 'P0001';
    END IF;

    -- Mark previous passwords as not current
    UPDATE user_passwords
    SET is_current = FALSE
    WHERE user_id   = NEW.user_id
      AND id       <> NEW.id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_password_reuse
    BEFORE INSERT ON user_passwords
    FOR EACH ROW EXECUTE FUNCTION fn_check_password_reuse();
