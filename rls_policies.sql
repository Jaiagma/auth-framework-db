-- =============================================================================
-- rls_policies.sql
-- Row-Level Security (RLS) policies for the multi-tenant authentication
-- framework. Each policy enforces strict tenant data isolation.
--
-- Convention:
--   • current_setting('app.current_tenant_id', TRUE) holds the active tenant.
--   • current_setting('app.current_user_id', TRUE) holds the authenticated user.
--   • current_setting('app.current_role', TRUE) holds the user role.
--
-- Super-admins (role = 'super_admin') bypass tenant-scoped policies via a
-- separate permissive policy on each table.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: is the current user a super-admin?
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_is_super_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT current_setting('app.current_role', TRUE) = 'super_admin';
$$;

-- ---------------------------------------------------------------------------
-- Helper: current tenant UUID (NULL-safe)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_current_tenant_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT current_setting('app.current_tenant_id', TRUE)::UUID;
$$;

-- ---------------------------------------------------------------------------
-- Helper: current user UUID (NULL-safe)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_current_user_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT current_setting('app.current_user_id', TRUE)::UUID;
$$;

-- ===========================================================================
-- TENANTS
-- ===========================================================================
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_tenants_tenant_isolation ON tenants
    AS RESTRICTIVE
    USING (id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_tenants_super_admin ON tenants
    AS PERMISSIVE
    TO PUBLIC
    USING (fn_is_super_admin());

-- ===========================================================================
-- TENANT DOMAINS
-- ===========================================================================
ALTER TABLE tenant_domains ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_tenant_domains_isolation ON tenant_domains
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- USERS
-- ===========================================================================
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

-- Tenant isolation: users only see users in their tenant
CREATE POLICY rls_users_tenant_isolation ON users
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- End-users can only see / update themselves
CREATE POLICY rls_users_self ON users
    AS PERMISSIVE
    USING (
        id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin','developer')
    );

-- ===========================================================================
-- USER PASSWORDS
-- ===========================================================================
ALTER TABLE user_passwords ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_user_passwords_isolation ON user_passwords
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_user_passwords_self ON user_passwords
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- USER ROLES
-- ===========================================================================
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_user_roles_isolation ON user_roles
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- APPLICATIONS
-- ===========================================================================
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_applications_isolation ON applications
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- SESSIONS
-- ===========================================================================
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_sessions_isolation ON sessions
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- End-users see only their own sessions
CREATE POLICY rls_sessions_self ON sessions
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- DEVICES
-- ===========================================================================
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_devices_isolation ON devices
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_devices_self ON devices
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- MFA DEVICES
-- ===========================================================================
ALTER TABLE mfa_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_mfa_devices_isolation ON mfa_devices
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_mfa_devices_self ON mfa_devices
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- MFA RECOVERY CODES
-- ===========================================================================
ALTER TABLE mfa_recovery_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_mfa_recovery_codes_isolation ON mfa_recovery_codes
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_mfa_recovery_codes_self ON mfa_recovery_codes
    AS PERMISSIVE
    USING (user_id = fn_current_user_id() OR fn_is_super_admin());

-- ===========================================================================
-- MFA CHALLENGES
-- ===========================================================================
ALTER TABLE mfa_challenges ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_mfa_challenges_isolation ON mfa_challenges
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- OAUTH SCOPES
-- ===========================================================================
ALTER TABLE oauth_scopes ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_oauth_scopes_isolation ON oauth_scopes
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- OAUTH AUTHORIZATION CODES
-- ===========================================================================
ALTER TABLE oauth_authorization_codes ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_oauth_authorization_codes_isolation ON oauth_authorization_codes
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- OAUTH TOKENS
-- ===========================================================================
ALTER TABLE oauth_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_oauth_tokens_isolation ON oauth_tokens
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_oauth_tokens_self ON oauth_tokens
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- OAUTH REFRESH TOKENS
-- ===========================================================================
ALTER TABLE oauth_refresh_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_oauth_refresh_tokens_isolation ON oauth_refresh_tokens
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- API KEYS
-- ===========================================================================
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_api_keys_isolation ON api_keys
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- IDENTITY PROVIDERS
-- ===========================================================================
ALTER TABLE identity_providers ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_identity_providers_isolation ON identity_providers
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- OIDC CONFIGURATIONS
-- ===========================================================================
ALTER TABLE oidc_configurations ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_oidc_configurations_isolation ON oidc_configurations
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- SAML CONFIGURATIONS
-- ===========================================================================
ALTER TABLE saml_configurations ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_saml_configurations_isolation ON saml_configurations
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- FEDERATED IDENTITIES
-- ===========================================================================
ALTER TABLE federated_identities ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_federated_identities_isolation ON federated_identities
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_federated_identities_self ON federated_identities
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- SSO SESSIONS
-- ===========================================================================
ALTER TABLE sso_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_sso_sessions_isolation ON sso_sessions
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- USER LOCALIZATION PREFERENCES
-- ===========================================================================
ALTER TABLE user_localization_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_user_localization_preferences_isolation ON user_localization_preferences
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_user_localization_preferences_self ON user_localization_preferences
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- TENANT REGIONAL SETTINGS
-- ===========================================================================
ALTER TABLE tenant_regional_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_tenant_regional_settings_isolation ON tenant_regional_settings
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- UI TRANSLATIONS
-- ===========================================================================
ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_ui_translations_isolation ON ui_translations
    AS RESTRICTIVE
    USING (tenant_id IS NULL OR tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- AUDIT LOGS
-- ===========================================================================
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_audit_logs_isolation ON audit_logs
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- End-users may only see their own audit entries
CREATE POLICY rls_audit_logs_self ON audit_logs
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- SECURITY EVENTS
-- ===========================================================================
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_security_events_isolation ON security_events
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- End-users see only their own events
CREATE POLICY rls_security_events_self ON security_events
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- USER CONSENTS
-- ===========================================================================
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_user_consents_isolation ON user_consents
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_user_consents_self ON user_consents
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- DATA RETENTION POLICIES (admin only)
-- ===========================================================================
ALTER TABLE data_retention_policies ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_data_retention_policies_isolation ON data_retention_policies
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- PII DELETION REQUESTS
-- ===========================================================================
ALTER TABLE pii_deletion_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_pii_deletion_requests_isolation ON pii_deletion_requests
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_pii_deletion_requests_self ON pii_deletion_requests
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- DATA EXPORT REQUESTS
-- ===========================================================================
ALTER TABLE data_export_requests ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_data_export_requests_isolation ON data_export_requests
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

CREATE POLICY rls_data_export_requests_self ON data_export_requests
    AS PERMISSIVE
    USING (
        user_id = fn_current_user_id()
        OR current_setting('app.current_role', TRUE) IN ('tenant_admin','super_admin')
    );

-- ===========================================================================
-- WEBHOOKS
-- ===========================================================================
ALTER TABLE webhooks ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_webhooks_isolation ON webhooks
    AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- API KEYS (application-scoped creation)
-- ===========================================================================
ALTER TABLE application_scopes ENABLE ROW LEVEL SECURITY;

CREATE POLICY rls_application_scopes_isolation ON application_scopes
    AS RESTRICTIVE
    USING (
        EXISTS (
            SELECT 1 FROM applications a
            WHERE a.id = application_scopes.application_id
              AND (a.tenant_id = fn_current_tenant_id() OR fn_is_super_admin())
        )
    );
