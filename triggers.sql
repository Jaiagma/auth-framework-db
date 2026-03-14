-- ============================================================
-- triggers.sql
-- Automated triggers for the multi-tenant authentication
-- framework: audit logging, timestamp management, and data
-- validation.
--
-- Prerequisites: enums.sql + schema.sql + functions.sql
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. updated_at auto-update triggers
--    Applied to every table that has an updated_at column.
-- ────────────────────────────────────────────────────────────

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tenant_settings_updated_at
    BEFORE UPDATE ON tenant_settings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_organizations_updated_at
    BEFORE UPDATE ON organizations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_applications_updated_at
    BEFORE UPDATE ON applications
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_roles_updated_at
    BEFORE UPDATE ON roles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_credentials_updated_at
    BEFORE UPDATE ON user_credentials
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_mfa_devices_updated_at
    BEFORE UPDATE ON mfa_devices
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_identity_providers_updated_at
    BEFORE UPDATE ON identity_providers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_saml_configurations_updated_at
    BEFORE UPDATE ON saml_configurations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_oidc_configurations_updated_at
    BEFORE UPDATE ON oidc_configurations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_localization_preferences_updated_at
    BEFORE UPDATE ON user_localization_preferences
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_tenant_regional_settings_updated_at
    BEFORE UPDATE ON tenant_regional_settings
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_ui_translations_updated_at
    BEFORE UPDATE ON ui_translations
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_user_consents_updated_at
    BEFORE UPDATE ON user_consents
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_data_retention_policies_updated_at
    BEFORE UPDATE ON data_retention_policies
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pii_deletion_requests_updated_at
    BEFORE UPDATE ON pii_deletion_requests
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_security_events_updated_at
    BEFORE UPDATE ON security_events
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_rate_limit_configs_updated_at
    BEFORE UPDATE ON rate_limit_configs
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_pii_data_classifications_updated_at
    BEFORE UPDATE ON pii_data_classifications
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_api_keys_updated_at
    BEFORE UPDATE ON api_keys
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_federated_identities_updated_at
    BEFORE UPDATE ON federated_identities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ────────────────────────────────────────────────────────────
-- 2. Audit-log triggers
--    Write to audit_logs on INSERT / UPDATE / DELETE for
--    sensitive tables.
-- ────────────────────────────────────────────────────────────

-- Generic audit trigger function; table-specific logic below.
CREATE OR REPLACE FUNCTION audit_trigger_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER   -- runs as owner so it can bypass RLS when writing audit_logs
AS $$
DECLARE
    v_tenant_id  UUID;
    v_event_type audit_event_type;
    v_resource   TEXT := TG_TABLE_NAME;
    v_resource_id TEXT;
    v_metadata   JSONB;
    v_actor_id   UUID;
BEGIN
    -- Determine actor from session setting
    v_actor_id := NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID;

    IF TG_OP = 'INSERT' THEN
        -- Try to extract tenant_id and id from the new row
        BEGIN
            v_tenant_id   := (row_to_json(NEW) ->> 'tenant_id')::UUID;
            v_resource_id := row_to_json(NEW) ->> 'id';
        EXCEPTION WHEN others THEN NULL;
        END;
        v_metadata := jsonb_build_object('operation', 'INSERT');
    ELSIF TG_OP = 'UPDATE' THEN
        BEGIN
            v_tenant_id   := (row_to_json(NEW) ->> 'tenant_id')::UUID;
            v_resource_id := row_to_json(NEW) ->> 'id';
        EXCEPTION WHEN others THEN NULL;
        END;
        v_metadata := jsonb_build_object('operation', 'UPDATE');
    ELSIF TG_OP = 'DELETE' THEN
        BEGIN
            v_tenant_id   := (row_to_json(OLD) ->> 'tenant_id')::UUID;
            v_resource_id := row_to_json(OLD) ->> 'id';
        EXCEPTION WHEN others THEN NULL;
        END;
        v_metadata := jsonb_build_object('operation', 'DELETE');
    END IF;

    -- Only log if we can determine the tenant
    IF v_tenant_id IS NOT NULL THEN
        -- Map table / operation to event type using a sensible default
        v_event_type := CASE
            WHEN TG_TABLE_NAME = 'users'           AND TG_OP = 'INSERT' THEN 'user_created'
            WHEN TG_TABLE_NAME = 'users'           AND TG_OP = 'UPDATE' THEN 'user_updated'
            WHEN TG_TABLE_NAME = 'users'           AND TG_OP = 'DELETE' THEN 'user_deleted'
            WHEN TG_TABLE_NAME = 'user_sessions'   AND TG_OP = 'INSERT' THEN 'login_success'
            WHEN TG_TABLE_NAME = 'user_sessions'   AND TG_OP = 'UPDATE' THEN 'session_revoked'
            WHEN TG_TABLE_NAME = 'mfa_devices'     AND TG_OP = 'INSERT' THEN 'mfa_enrolled'
            WHEN TG_TABLE_NAME = 'mfa_devices'     AND TG_OP = 'DELETE' THEN 'mfa_revoked'
            WHEN TG_TABLE_NAME = 'oauth_tokens'    AND TG_OP = 'INSERT' THEN 'token_issued'
            WHEN TG_TABLE_NAME = 'oauth_tokens'    AND TG_OP = 'UPDATE' THEN 'token_revoked'
            WHEN TG_TABLE_NAME = 'federated_identities' AND TG_OP = 'INSERT' THEN 'idp_linked'
            WHEN TG_TABLE_NAME = 'federated_identities' AND TG_OP = 'DELETE' THEN 'idp_unlinked'
            WHEN TG_TABLE_NAME = 'user_consents'   AND TG_OP = 'INSERT' THEN 'consent_given'
            WHEN TG_TABLE_NAME = 'user_consents'   AND TG_OP = 'UPDATE' THEN 'consent_withdrawn'
            WHEN TG_TABLE_NAME = 'pii_deletion_requests' AND TG_OP = 'INSERT' THEN 'data_deletion_requested'
            WHEN TG_TABLE_NAME = 'api_keys'        AND TG_OP = 'INSERT' THEN 'api_key_created'
            WHEN TG_TABLE_NAME = 'api_keys'        AND TG_OP = 'UPDATE' THEN 'api_key_revoked'
            WHEN TG_TABLE_NAME = 'user_roles'      AND TG_OP = 'INSERT' THEN 'role_assigned'
            WHEN TG_TABLE_NAME = 'user_roles'      AND TG_OP = 'DELETE' THEN 'role_revoked'
            ELSE 'user_updated'   -- safe fallback
        END;

        INSERT INTO audit_logs (
            tenant_id,
            event_type,
            actor_user_id,
            actor_type,
            resource_type,
            resource_id,
            metadata
        )
        VALUES (
            v_tenant_id,
            v_event_type,
            v_actor_id,
            COALESCE(current_setting('app.actor_type', TRUE), 'user'),
            v_resource,
            v_resource_id,
            v_metadata
        );
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Attach audit trigger to sensitive tables
CREATE TRIGGER trg_audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_user_sessions
    AFTER INSERT OR UPDATE ON user_sessions
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_mfa_devices
    AFTER INSERT OR DELETE ON mfa_devices
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_oauth_tokens
    AFTER INSERT OR UPDATE ON oauth_tokens
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_federated_identities
    AFTER INSERT OR DELETE ON federated_identities
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_user_consents
    AFTER INSERT OR UPDATE ON user_consents
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_pii_deletion_requests
    AFTER INSERT ON pii_deletion_requests
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_api_keys
    AFTER INSERT OR UPDATE ON api_keys
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

CREATE TRIGGER trg_audit_user_roles
    AFTER INSERT OR DELETE ON user_roles
    FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

-- ────────────────────────────────────────────────────────────
-- 3. User account-lock auto-expiry trigger
--    Unlock the account when locked_until has passed.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION auto_unlock_user()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'locked'
       AND NEW.locked_until IS NOT NULL
       AND NEW.locked_until <= now() THEN
        NEW.status              := 'active';
        NEW.locked_until        := NULL;
        NEW.failed_login_count  := 0;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_unlock_user
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION auto_unlock_user();

-- ────────────────────────────────────────────────────────────
-- 4. Prevent deletion of system roles
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION prevent_system_role_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.is_system = TRUE THEN
        RAISE EXCEPTION 'Cannot delete a system role: %', OLD.name;
    END IF;
    RETURN OLD;
END;
$$;

CREATE TRIGGER trg_prevent_system_role_deletion
    BEFORE DELETE ON roles
    FOR EACH ROW EXECUTE FUNCTION prevent_system_role_deletion();

-- ────────────────────────────────────────────────────────────
-- 5. Password history enforcement
--    Prevents reuse of the last N passwords.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION check_password_history()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_hist_count INT;
    v_hist TEXT[];
    v_h    TEXT;
BEGIN
    -- Only enforce on password credential type
    IF NEW.credential_type <> 'password'
       OR NEW.password_hash IS NULL THEN
        RETURN NEW;
    END IF;

    -- Check against stored history
    FOREACH v_h IN ARRAY COALESCE(OLD.password_history, '{}')
    LOOP
        IF crypt(NEW.password_hash, v_h) = v_h THEN
            RAISE EXCEPTION 'Password was recently used. Please choose a different password.';
        END IF;
    END LOOP;

    -- Prepend old hash to history, keep last 10
    IF OLD.password_hash IS NOT NULL THEN
        v_hist := ARRAY[OLD.password_hash] || COALESCE(OLD.password_history, '{}');
        NEW.password_history := v_hist[1:10];
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_check_password_history
    BEFORE UPDATE ON user_credentials
    FOR EACH ROW EXECUTE FUNCTION check_password_history();

-- ────────────────────────────────────────────────────────────
-- 6. Soft-delete cascade trigger
--    When a user is soft-deleted (deleted_at set), cascade
--    revocation of sessions, tokens, and MFA devices.
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION cascade_user_soft_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL THEN
        -- Revoke active sessions
        UPDATE user_sessions
        SET status     = 'revoked',
            revoked_at = now()
        WHERE user_id  = NEW.id AND status = 'active';

        -- Revoke active OAuth tokens
        UPDATE oauth_tokens
        SET status           = 'revoked',
            revoked_at       = now(),
            revocation_reason = 'user_soft_deleted'
        WHERE user_id = NEW.id AND status = 'active';

        -- Deactivate MFA devices
        UPDATE mfa_devices
        SET status     = 'revoked',
            updated_at = now()
        WHERE user_id = NEW.id AND status = 'active';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_cascade_user_soft_delete
    AFTER UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION cascade_user_soft_delete();

-- ────────────────────────────────────────────────────────────
-- 7. Enforce tenant max_users limit
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION enforce_tenant_max_users()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max    INT;
    v_count  INT;
BEGIN
    SELECT max_users INTO v_max
    FROM tenants
    WHERE id = NEW.tenant_id;

    IF v_max IS NULL THEN
        RETURN NEW;   -- no limit set
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM users
    WHERE tenant_id = NEW.tenant_id
      AND deleted_at IS NULL;

    IF v_count >= v_max THEN
        RAISE EXCEPTION 'Tenant has reached the maximum user limit of %', v_max;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_tenant_max_users
    BEFORE INSERT ON users
    FOR EACH ROW EXECUTE FUNCTION enforce_tenant_max_users();

-- ────────────────────────────────────────────────────────────
-- 8. Enforce tenant max_applications limit
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION enforce_tenant_max_applications()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_max   INT;
    v_count INT;
BEGIN
    SELECT max_applications INTO v_max
    FROM tenants
    WHERE id = NEW.tenant_id;

    IF v_max IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT COUNT(*) INTO v_count
    FROM applications
    WHERE tenant_id = NEW.tenant_id
      AND deleted_at IS NULL;

    IF v_count >= v_max THEN
        RAISE EXCEPTION 'Tenant has reached the maximum application limit of %', v_max;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enforce_tenant_max_applications
    BEFORE INSERT ON applications
    FOR EACH ROW EXECUTE FUNCTION enforce_tenant_max_applications();

-- ────────────────────────────────────────────────────────────
-- 9. Auto-expire OAuth authorisation codes (idempotent mark)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION mark_auth_code_used()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_used = TRUE AND OLD.is_used = FALSE THEN
        NEW.used_at := now();
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_mark_auth_code_used
    BEFORE UPDATE ON oauth_authorization_codes
    FOR EACH ROW EXECUTE FUNCTION mark_auth_code_used();

-- ────────────────────────────────────────────────────────────
-- 10. Set GDPR deletion deadline (30 calendar days by default)
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_deletion_deadline()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.deadline_at IS NULL THEN
        NEW.deadline_at := NEW.requested_at + INTERVAL '30 days';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_set_deletion_deadline
    BEFORE INSERT ON pii_deletion_requests
    FOR EACH ROW EXECUTE FUNCTION set_deletion_deadline();
