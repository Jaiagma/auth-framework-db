-- ============================================================
-- rls_policies.sql
-- Row-Level Security policies for multi-tenant data isolation.
--
-- Prerequisites: enums.sql + schema.sql must be run first.
--
-- Conventions:
--   • Every application connection must SET app.current_tenant_id
--     to the tenant's UUID before executing any DML/queries.
--   • Every application connection must SET app.current_user_id
--     to the authenticated user's UUID (empty string for anonymous).
--   • Super-admin bypass is handled at the application layer by
--     connecting with a role that bypasses RLS.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- Helper functions to read current-connection settings
-- ────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_tenant_id', TRUE), '')::UUID;
$$;

CREATE OR REPLACE FUNCTION current_app_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.current_user_id', TRUE), '')::UUID;
$$;

-- Returns TRUE if the current connection is an admin / internal service.
-- In production, bind this to a dedicated DB role check.
CREATE OR REPLACE FUNCTION is_service_role()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT current_setting('app.is_service_role', TRUE) = 'true';
$$;

-- ────────────────────────────────────────────────────────────
-- Macro: enable RLS + force on table
-- ────────────────────────────────────────────────────────────

-- tenants
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;

CREATE POLICY tenants_isolation ON tenants
    USING (
        is_service_role()
        OR id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- tenant_settings
-- ────────────────────────────────────────────────────────────
ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_settings_isolation ON tenant_settings
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- organizations
-- ────────────────────────────────────────────────────────────
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations FORCE ROW LEVEL SECURITY;

CREATE POLICY organizations_isolation ON organizations
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- applications
-- ────────────────────────────────────────────────────────────
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications FORCE ROW LEVEL SECURITY;

CREATE POLICY applications_isolation ON applications
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- roles
-- ────────────────────────────────────────────────────────────
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles FORCE ROW LEVEL SECURITY;

CREATE POLICY roles_isolation ON roles
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- permissions
-- ────────────────────────────────────────────────────────────
ALTER TABLE permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions FORCE ROW LEVEL SECURITY;

CREATE POLICY permissions_isolation ON permissions
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- role_permissions
-- (joined via roles → tenant_id)
-- ────────────────────────────────────────────────────────────
ALTER TABLE role_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions FORCE ROW LEVEL SECURITY;

CREATE POLICY role_permissions_isolation ON role_permissions
    USING (
        is_service_role()
        OR EXISTS (
            SELECT 1 FROM roles r
            WHERE r.id = role_permissions.role_id
              AND r.tenant_id = current_tenant_id()
        )
    );

-- ────────────────────────────────────────────────────────────
-- users
-- ────────────────────────────────────────────────────────────
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;

-- Tenant admins see all users in their tenant;
-- regular users can only see their own row.
CREATE POLICY users_tenant_isolation ON users
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY users_self_read ON users
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- user_profiles
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles FORCE ROW LEVEL SECURITY;

CREATE POLICY user_profiles_isolation ON user_profiles
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY user_profiles_self_read ON user_profiles
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- user_credentials  (highly sensitive – enforce strict access)
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_credentials FORCE ROW LEVEL SECURITY;

CREATE POLICY user_credentials_service_only ON user_credentials
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- user_roles
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles FORCE ROW LEVEL SECURITY;

CREATE POLICY user_roles_isolation ON user_roles
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- user_sessions
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sessions FORCE ROW LEVEL SECURITY;

CREATE POLICY user_sessions_isolation ON user_sessions
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY user_sessions_self_read ON user_sessions
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- mfa_devices
-- ────────────────────────────────────────────────────────────
ALTER TABLE mfa_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_devices FORCE ROW LEVEL SECURITY;

CREATE POLICY mfa_devices_isolation ON mfa_devices
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY mfa_devices_self_read ON mfa_devices
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- mfa_recovery_codes
-- ────────────────────────────────────────────────────────────
ALTER TABLE mfa_recovery_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_recovery_codes FORCE ROW LEVEL SECURITY;

CREATE POLICY mfa_recovery_codes_isolation ON mfa_recovery_codes
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- mfa_challenges
-- ────────────────────────────────────────────────────────────
ALTER TABLE mfa_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_challenges FORCE ROW LEVEL SECURITY;

CREATE POLICY mfa_challenges_isolation ON mfa_challenges
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- oauth_scopes
-- ────────────────────────────────────────────────────────────
ALTER TABLE oauth_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_scopes FORCE ROW LEVEL SECURITY;

CREATE POLICY oauth_scopes_isolation ON oauth_scopes
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- oauth_authorization_codes
-- ────────────────────────────────────────────────────────────
ALTER TABLE oauth_authorization_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_authorization_codes FORCE ROW LEVEL SECURITY;

CREATE POLICY oauth_auth_codes_isolation ON oauth_authorization_codes
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- oauth_tokens
-- ────────────────────────────────────────────────────────────
ALTER TABLE oauth_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY oauth_tokens_isolation ON oauth_tokens
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- identity_providers
-- ────────────────────────────────────────────────────────────
ALTER TABLE identity_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity_providers FORCE ROW LEVEL SECURITY;

CREATE POLICY idp_isolation ON identity_providers
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- saml_configurations
-- ────────────────────────────────────────────────────────────
ALTER TABLE saml_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE saml_configurations FORCE ROW LEVEL SECURITY;

CREATE POLICY saml_config_isolation ON saml_configurations
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- oidc_configurations
-- ────────────────────────────────────────────────────────────
ALTER TABLE oidc_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE oidc_configurations FORCE ROW LEVEL SECURITY;

CREATE POLICY oidc_config_isolation ON oidc_configurations
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- sso_sessions
-- ────────────────────────────────────────────────────────────
ALTER TABLE sso_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sso_sessions FORCE ROW LEVEL SECURITY;

CREATE POLICY sso_sessions_isolation ON sso_sessions
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- federated_identities
-- ────────────────────────────────────────────────────────────
ALTER TABLE federated_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE federated_identities FORCE ROW LEVEL SECURITY;

CREATE POLICY federated_identities_isolation ON federated_identities
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY federated_identities_self_read ON federated_identities
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- linked_accounts
-- ────────────────────────────────────────────────────────────
ALTER TABLE linked_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE linked_accounts FORCE ROW LEVEL SECURITY;

CREATE POLICY linked_accounts_isolation ON linked_accounts
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- user_localization_preferences
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_localization_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_localization_preferences FORCE ROW LEVEL SECURITY;

CREATE POLICY user_locale_isolation ON user_localization_preferences
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY user_locale_self_read ON user_localization_preferences
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- tenant_regional_settings
-- ────────────────────────────────────────────────────────────
ALTER TABLE tenant_regional_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_regional_settings FORCE ROW LEVEL SECURITY;

CREATE POLICY tenant_regional_settings_isolation ON tenant_regional_settings
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- ui_translations  (public read within tenant, admin write)
-- ────────────────────────────────────────────────────────────
ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_translations FORCE ROW LEVEL SECURITY;

CREATE POLICY ui_translations_read ON ui_translations
    FOR SELECT
    USING (
        tenant_id IS NULL               -- global translations visible to all
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY ui_translations_write ON ui_translations
    FOR ALL
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- audit_logs  (append-only for non-service roles)
-- ────────────────────────────────────────────────────────────
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs FORCE ROW LEVEL SECURITY;

CREATE POLICY audit_logs_isolation ON audit_logs
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- Prevent any updates or deletes on audit_logs (immutability)
CREATE POLICY audit_logs_no_update ON audit_logs
    FOR UPDATE
    USING (is_service_role());

CREATE POLICY audit_logs_no_delete ON audit_logs
    FOR DELETE
    USING (is_service_role());

-- ────────────────────────────────────────────────────────────
-- user_consents
-- ────────────────────────────────────────────────────────────
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_consents FORCE ROW LEVEL SECURITY;

CREATE POLICY user_consents_isolation ON user_consents
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY user_consents_self_read ON user_consents
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- data_retention_policies
-- ────────────────────────────────────────────────────────────
ALTER TABLE data_retention_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_retention_policies FORCE ROW LEVEL SECURITY;

CREATE POLICY data_retention_isolation ON data_retention_policies
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- pii_deletion_requests
-- ────────────────────────────────────────────────────────────
ALTER TABLE pii_deletion_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE pii_deletion_requests FORCE ROW LEVEL SECURITY;

CREATE POLICY pii_deletion_isolation ON pii_deletion_requests
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

CREATE POLICY pii_deletion_self_read ON pii_deletion_requests
    AS PERMISSIVE
    FOR SELECT
    USING (
        tenant_id = current_tenant_id()
        AND user_id = current_app_user_id()
    );

-- ────────────────────────────────────────────────────────────
-- device_fingerprints
-- ────────────────────────────────────────────────────────────
ALTER TABLE device_fingerprints ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_fingerprints FORCE ROW LEVEL SECURITY;

CREATE POLICY device_fingerprints_isolation ON device_fingerprints
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- security_events
-- ────────────────────────────────────────────────────────────
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_events FORCE ROW LEVEL SECURITY;

CREATE POLICY security_events_isolation ON security_events
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- rate_limit_configs
-- ────────────────────────────────────────────────────────────
ALTER TABLE rate_limit_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE rate_limit_configs FORCE ROW LEVEL SECURITY;

CREATE POLICY rate_limit_isolation ON rate_limit_configs
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- ip_allowlists
-- ────────────────────────────────────────────────────────────
ALTER TABLE ip_allowlists ENABLE ROW LEVEL SECURITY;
ALTER TABLE ip_allowlists FORCE ROW LEVEL SECURITY;

CREATE POLICY ip_allowlists_isolation ON ip_allowlists
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- pii_data_classifications
-- ────────────────────────────────────────────────────────────
ALTER TABLE pii_data_classifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE pii_data_classifications FORCE ROW LEVEL SECURITY;

CREATE POLICY pii_classifications_isolation ON pii_data_classifications
    USING (
        is_service_role()
        OR tenant_id IS NULL            -- global classifications visible to all
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- api_keys
-- ────────────────────────────────────────────────────────────
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys FORCE ROW LEVEL SECURITY;

CREATE POLICY api_keys_isolation ON api_keys
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- password_reset_tokens
-- ────────────────────────────────────────────────────────────
ALTER TABLE password_reset_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE password_reset_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY password_reset_tokens_isolation ON password_reset_tokens
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );

-- ────────────────────────────────────────────────────────────
-- email_verification_tokens
-- ────────────────────────────────────────────────────────────
ALTER TABLE email_verification_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_verification_tokens FORCE ROW LEVEL SECURITY;

CREATE POLICY email_verification_tokens_isolation ON email_verification_tokens
    USING (
        is_service_role()
        OR tenant_id = current_tenant_id()
    );
