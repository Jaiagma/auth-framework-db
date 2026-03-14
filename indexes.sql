-- ============================================================
-- indexes.sql
-- Performance indexes for the multi-tenant authentication
-- framework.
--
-- Prerequisites: enums.sql + schema.sql must be run first.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- tenants
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_tenants_slug        ON tenants (slug);
CREATE INDEX idx_tenants_status      ON tenants (status) WHERE status <> 'deleted';
CREATE INDEX idx_tenants_created_at  ON tenants (created_at DESC);

-- ────────────────────────────────────────────────────────────
-- organizations
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_organizations_tenant     ON organizations (tenant_id);
CREATE INDEX idx_organizations_parent     ON organizations (parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX idx_organizations_deleted_at ON organizations (tenant_id, deleted_at) WHERE deleted_at IS NULL;

-- ────────────────────────────────────────────────────────────
-- applications
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_applications_tenant       ON applications (tenant_id);
CREATE INDEX idx_applications_client_id    ON applications (client_id);
CREATE INDEX idx_applications_active       ON applications (tenant_id, is_active) WHERE is_active = TRUE;
CREATE INDEX idx_applications_deleted_at   ON applications (tenant_id, deleted_at) WHERE deleted_at IS NULL;

-- ────────────────────────────────────────────────────────────
-- roles & permissions
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_roles_tenant      ON roles (tenant_id);
CREATE INDEX idx_permissions_tenant ON permissions (tenant_id);
CREATE INDEX idx_role_permissions_permission ON role_permissions (permission_id);

-- ────────────────────────────────────────────────────────────
-- users
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_users_tenant          ON users (tenant_id);
CREATE INDEX idx_users_email_hash      ON users (tenant_id, email_hash);
CREATE INDEX idx_users_username        ON users (tenant_id, username) WHERE username IS NOT NULL;
CREATE INDEX idx_users_status          ON users (tenant_id, status);
CREATE INDEX idx_users_created_at      ON users (tenant_id, created_at DESC);
CREATE INDEX idx_users_last_login      ON users (tenant_id, last_login_at DESC) WHERE last_login_at IS NOT NULL;
CREATE INDEX idx_users_locked          ON users (tenant_id, locked_until) WHERE locked_until IS NOT NULL;
CREATE INDEX idx_users_deleted_at      ON users (tenant_id, deleted_at) WHERE deleted_at IS NULL;

-- ────────────────────────────────────────────────────────────
-- user_profiles
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_user_profiles_user   ON user_profiles (user_id);
CREATE INDEX idx_user_profiles_tenant ON user_profiles (tenant_id);

-- ────────────────────────────────────────────────────────────
-- user_credentials
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_user_credentials_user   ON user_credentials (user_id, credential_type);
CREATE INDEX idx_user_credentials_tenant ON user_credentials (tenant_id);

-- ────────────────────────────────────────────────────────────
-- user_roles
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_user_roles_user   ON user_roles (user_id);
CREATE INDEX idx_user_roles_role   ON user_roles (role_id);
CREATE INDEX idx_user_roles_tenant ON user_roles (tenant_id);

-- ────────────────────────────────────────────────────────────
-- user_sessions
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_sessions_user       ON user_sessions (user_id, status);
CREATE INDEX idx_sessions_tenant     ON user_sessions (tenant_id, status);
CREATE INDEX idx_sessions_app        ON user_sessions (application_id) WHERE application_id IS NOT NULL;
CREATE INDEX idx_sessions_expires    ON user_sessions (expires_at) WHERE status = 'active';
CREATE INDEX idx_sessions_device     ON user_sessions (device_fingerprint_id) WHERE device_fingerprint_id IS NOT NULL;
CREATE INDEX idx_sessions_sso        ON user_sessions (sso_session_id) WHERE sso_session_id IS NOT NULL;
-- token_hash already has UNIQUE index on the column definition

-- ────────────────────────────────────────────────────────────
-- mfa_devices
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_mfa_devices_user   ON mfa_devices (user_id, method, status);
CREATE INDEX idx_mfa_devices_tenant ON mfa_devices (tenant_id);
CREATE INDEX idx_mfa_devices_active ON mfa_devices (user_id, status) WHERE status = 'active';

-- ────────────────────────────────────────────────────────────
-- mfa_recovery_codes
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_mfa_recovery_user   ON mfa_recovery_codes (user_id, used);
CREATE INDEX idx_mfa_recovery_tenant ON mfa_recovery_codes (tenant_id);

-- ────────────────────────────────────────────────────────────
-- mfa_challenges
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_mfa_challenges_user    ON mfa_challenges (user_id, is_verified);
CREATE INDEX idx_mfa_challenges_expires ON mfa_challenges (expires_at) WHERE is_verified = FALSE;

-- ────────────────────────────────────────────────────────────
-- oauth_scopes
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_oauth_scopes_tenant ON oauth_scopes (tenant_id);

-- ────────────────────────────────────────────────────────────
-- oauth_authorization_codes
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_auth_codes_app     ON oauth_authorization_codes (application_id);
CREATE INDEX idx_auth_codes_user    ON oauth_authorization_codes (user_id);
CREATE INDEX idx_auth_codes_tenant  ON oauth_authorization_codes (tenant_id);
CREATE INDEX idx_auth_codes_expires ON oauth_authorization_codes (expires_at) WHERE is_used = FALSE;

-- ────────────────────────────────────────────────────────────
-- oauth_tokens
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_tokens_user        ON oauth_tokens (user_id, token_type, status);
CREATE INDEX idx_tokens_app         ON oauth_tokens (application_id, status);
CREATE INDEX idx_tokens_tenant      ON oauth_tokens (tenant_id, status);
CREATE INDEX idx_tokens_session     ON oauth_tokens (session_id) WHERE session_id IS NOT NULL;
CREATE INDEX idx_tokens_expires     ON oauth_tokens (expires_at) WHERE status = 'active';
CREATE INDEX idx_tokens_parent      ON oauth_tokens (parent_token_id) WHERE parent_token_id IS NOT NULL;

-- ────────────────────────────────────────────────────────────
-- identity_providers
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_idp_tenant  ON identity_providers (tenant_id, status);
CREATE INDEX idx_idp_type    ON identity_providers (tenant_id, provider_type);

-- ────────────────────────────────────────────────────────────
-- sso_sessions
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_sso_sessions_user    ON sso_sessions (user_id, status);
CREATE INDEX idx_sso_sessions_tenant  ON sso_sessions (tenant_id, status);
CREATE INDEX idx_sso_sessions_expires ON sso_sessions (expires_at) WHERE status = 'active';

-- ────────────────────────────────────────────────────────────
-- federated_identities
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_fed_id_user   ON federated_identities (user_id, status);
CREATE INDEX idx_fed_id_idp    ON federated_identities (idp_id, subject);
CREATE INDEX idx_fed_id_tenant ON federated_identities (tenant_id);

-- ────────────────────────────────────────────────────────────
-- user_localization_preferences
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_user_locale_tenant ON user_localization_preferences (tenant_id);

-- ────────────────────────────────────────────────────────────
-- ui_translations
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_ui_trans_lang      ON ui_translations (language_code);
CREATE INDEX idx_ui_trans_ns        ON ui_translations (tenant_id, language_code, namespace);
-- Trigram index for substring / fuzzy search of translation keys
CREATE INDEX idx_ui_trans_key_trgm  ON ui_translations USING GIN (key gin_trgm_ops);

-- ────────────────────────────────────────────────────────────
-- audit_logs
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_audit_tenant      ON audit_logs (tenant_id, created_at DESC);
CREATE INDEX idx_audit_actor       ON audit_logs (actor_user_id, created_at DESC) WHERE actor_user_id IS NOT NULL;
CREATE INDEX idx_audit_event_type  ON audit_logs (tenant_id, event_type);
CREATE INDEX idx_audit_resource    ON audit_logs (tenant_id, resource_type, resource_id);
CREATE INDEX idx_audit_ip          ON audit_logs (ip_address) WHERE ip_address IS NOT NULL;
CREATE INDEX idx_audit_severity    ON audit_logs (tenant_id, severity) WHERE severity IN ('warning','error','critical');
-- BRIN index for time-series scans on the immutable append-only log
CREATE INDEX idx_audit_created_brin ON audit_logs USING BRIN (created_at);

-- ────────────────────────────────────────────────────────────
-- user_consents
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_consents_user   ON user_consents (user_id, consent_type);
CREATE INDEX idx_consents_tenant ON user_consents (tenant_id, status);

-- ────────────────────────────────────────────────────────────
-- pii_deletion_requests
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_pii_del_req_user   ON pii_deletion_requests (user_id, status);
CREATE INDEX idx_pii_del_req_tenant ON pii_deletion_requests (tenant_id, status);
CREATE INDEX idx_pii_del_req_deadline ON pii_deletion_requests (deadline_at) WHERE status IN ('pending','in_progress');

-- ────────────────────────────────────────────────────────────
-- device_fingerprints
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_device_fp_user   ON device_fingerprints (user_id, trust_level) WHERE user_id IS NOT NULL;
CREATE INDEX idx_device_fp_tenant ON device_fingerprints (tenant_id);

-- ────────────────────────────────────────────────────────────
-- security_events
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_sec_events_user   ON security_events (user_id, event_type) WHERE user_id IS NOT NULL;
CREATE INDEX idx_sec_events_tenant ON security_events (tenant_id, risk_level, status);
CREATE INDEX idx_sec_events_ip     ON security_events (ip_address) WHERE ip_address IS NOT NULL;
CREATE INDEX idx_sec_events_open   ON security_events (tenant_id, created_at DESC) WHERE status = 'open';

-- ────────────────────────────────────────────────────────────
-- api_keys
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_api_keys_tenant ON api_keys (tenant_id, is_active);
CREATE INDEX idx_api_keys_user   ON api_keys (user_id) WHERE user_id IS NOT NULL;
CREATE INDEX idx_api_keys_app    ON api_keys (application_id) WHERE application_id IS NOT NULL;
-- key_hash UNIQUE index already created in schema.sql

-- ────────────────────────────────────────────────────────────
-- password_reset_tokens
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_pwd_reset_user    ON password_reset_tokens (user_id, is_used);
CREATE INDEX idx_pwd_reset_expires ON password_reset_tokens (expires_at) WHERE is_used = FALSE;

-- ────────────────────────────────────────────────────────────
-- email_verification_tokens
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_email_ver_user    ON email_verification_tokens (user_id, is_used);
CREATE INDEX idx_email_ver_expires ON email_verification_tokens (expires_at) WHERE is_used = FALSE;

-- ────────────────────────────────────────────────────────────
-- ip_allowlists
-- ────────────────────────────────────────────────────────────
CREATE INDEX idx_ip_allowlists_tenant  ON ip_allowlists (tenant_id, is_blocklist);
CREATE INDEX idx_ip_allowlists_expires ON ip_allowlists (expires_at) WHERE expires_at IS NOT NULL;
