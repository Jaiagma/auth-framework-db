-- =============================================================================
-- indexes.sql
-- Performance indexes for the multi-tenant authentication framework.
-- All primary keys (UUID v7) already have implicit B-tree indexes.
-- These supplementary indexes target the most common query patterns.
-- =============================================================================

-- ===========================================================================
-- TENANTS
-- ===========================================================================
CREATE INDEX idx_tenants_slug           ON tenants (slug);
CREATE INDEX idx_tenants_status         ON tenants (status) WHERE status <> 'deleted';
CREATE INDEX idx_tenant_domains_domain  ON tenant_domains (domain);
CREATE INDEX idx_tenant_domains_tenant  ON tenant_domains (tenant_id);

-- ===========================================================================
-- USERS
-- UUID v7 pk gives time-ordered clustering. Supplementary:
-- ===========================================================================
CREATE INDEX idx_users_tenant_status
    ON users (tenant_id, status)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_users_email_hash
    ON users (tenant_id, email_hash);

CREATE INDEX idx_users_phone_hash
    ON users (tenant_id, phone_hash)
    WHERE phone_hash IS NOT NULL;

CREATE INDEX idx_users_external_id
    ON users (tenant_id, external_id)
    WHERE external_id IS NOT NULL;

CREATE INDEX idx_users_created_at
    ON users (tenant_id, created_at DESC);

-- ===========================================================================
-- USER PASSWORDS
-- ===========================================================================
CREATE INDEX idx_user_passwords_user_current
    ON user_passwords (user_id, is_current)
    WHERE is_current = TRUE;

-- ===========================================================================
-- APPLICATIONS
-- ===========================================================================
CREATE INDEX idx_applications_client_id
    ON applications (client_id);

CREATE INDEX idx_applications_tenant_slug
    ON applications (tenant_id, slug);

CREATE INDEX idx_applications_tenant_active
    ON applications (tenant_id, is_active)
    WHERE is_active = TRUE;

-- ===========================================================================
-- SESSIONS
-- ===========================================================================
CREATE INDEX idx_sessions_token_hash
    ON sessions (session_token_hash);

CREATE INDEX idx_sessions_user_active
    ON sessions (user_id, status, expires_at)
    WHERE status = 'active';

CREATE INDEX idx_sessions_tenant_user
    ON sessions (tenant_id, user_id);

CREATE INDEX idx_sessions_expires_at
    ON sessions (expires_at)
    WHERE status = 'active';

CREATE INDEX idx_sessions_device
    ON sessions (device_id)
    WHERE device_id IS NOT NULL;

-- ===========================================================================
-- DEVICES
-- ===========================================================================
CREATE INDEX idx_devices_user
    ON devices (user_id, trust_status);

CREATE INDEX idx_devices_fingerprint
    ON devices (tenant_id, fingerprint_hash);

-- ===========================================================================
-- MFA DEVICES
-- ===========================================================================
CREATE INDEX idx_mfa_devices_user_active
    ON mfa_devices (user_id, status)
    WHERE status = 'active';

CREATE INDEX idx_mfa_devices_webauthn_credential
    ON mfa_devices (credential_id)
    WHERE credential_id IS NOT NULL;

-- ===========================================================================
-- MFA RECOVERY CODES
-- ===========================================================================
CREATE INDEX idx_mfa_recovery_codes_user_unused
    ON mfa_recovery_codes (user_id)
    WHERE used = FALSE;

-- ===========================================================================
-- MFA CHALLENGES
-- ===========================================================================
CREATE INDEX idx_mfa_challenges_user_unverified
    ON mfa_challenges (user_id, expires_at)
    WHERE verified = FALSE;

-- ===========================================================================
-- OAUTH AUTHORIZATION CODES
-- ===========================================================================
CREATE INDEX idx_oauth_auth_codes_hash
    ON oauth_authorization_codes (code_hash);

CREATE INDEX idx_oauth_auth_codes_user_app
    ON oauth_authorization_codes (user_id, application_id, used, expires_at);

-- ===========================================================================
-- OAUTH TOKENS
-- ===========================================================================
CREATE INDEX idx_oauth_tokens_hash
    ON oauth_tokens (token_hash);

CREATE INDEX idx_oauth_tokens_user_active
    ON oauth_tokens (user_id, status, expires_at)
    WHERE status = 'active';

CREATE INDEX idx_oauth_tokens_app
    ON oauth_tokens (application_id, tenant_id, status);

CREATE INDEX idx_oauth_tokens_expires
    ON oauth_tokens (expires_at)
    WHERE status = 'active';

-- ===========================================================================
-- OAUTH REFRESH TOKENS
-- ===========================================================================
CREATE INDEX idx_oauth_refresh_tokens_hash
    ON oauth_refresh_tokens (token_hash);

CREATE INDEX idx_oauth_refresh_tokens_access_token
    ON oauth_refresh_tokens (access_token_id);

-- ===========================================================================
-- API KEYS
-- ===========================================================================
CREATE INDEX idx_api_keys_hash
    ON api_keys (key_hash);

CREATE INDEX idx_api_keys_prefix
    ON api_keys (key_prefix, status);

CREATE INDEX idx_api_keys_tenant_active
    ON api_keys (tenant_id, status)
    WHERE status = 'active';

-- ===========================================================================
-- IDENTITY PROVIDERS
-- ===========================================================================
CREATE INDEX idx_identity_providers_tenant_active
    ON identity_providers (tenant_id, status)
    WHERE status = 'active';

CREATE INDEX idx_identity_providers_type
    ON identity_providers (tenant_id, provider_type);

-- ===========================================================================
-- OIDC CONFIGURATIONS
-- ===========================================================================
CREATE INDEX idx_oidc_configurations_provider
    ON oidc_configurations (provider_id);

CREATE INDEX idx_oidc_configurations_tenant
    ON oidc_configurations (tenant_id);

-- ===========================================================================
-- SAML CONFIGURATIONS
-- ===========================================================================
CREATE INDEX idx_saml_configurations_provider
    ON saml_configurations (provider_id);

CREATE INDEX idx_saml_configurations_tenant
    ON saml_configurations (tenant_id);

CREATE INDEX idx_saml_configurations_sp_entity
    ON saml_configurations (sp_entity_id);

-- ===========================================================================
-- FEDERATED IDENTITIES
-- ===========================================================================
CREATE INDEX idx_federated_identities_user
    ON federated_identities (user_id, provider_id);

CREATE INDEX idx_federated_identities_subject
    ON federated_identities (tenant_id, provider_id, external_subject);

CREATE INDEX idx_federated_identities_email_hash
    ON federated_identities (tenant_id, external_email_hash)
    WHERE external_email_hash IS NOT NULL;

-- ===========================================================================
-- SSO SESSIONS
-- ===========================================================================
CREATE INDEX idx_sso_sessions_user_active
    ON sso_sessions (user_id, status, expires_at)
    WHERE status = 'active';

CREATE INDEX idx_sso_sessions_tenant
    ON sso_sessions (tenant_id, status);

CREATE INDEX idx_sso_sessions_idp_session
    ON sso_sessions (idp_session_id)
    WHERE idp_session_id IS NOT NULL;

-- ===========================================================================
-- USER LOCALIZATION PREFERENCES
-- ===========================================================================
CREATE INDEX idx_user_localization_user
    ON user_localization_preferences (user_id);

-- ===========================================================================
-- UI TRANSLATIONS
-- ===========================================================================
CREATE INDEX idx_ui_translations_lookup
    ON ui_translations (tenant_id, language_id, namespace, key);

-- GIN index for full-text translation search
CREATE INDEX idx_ui_translations_value_fts
    ON ui_translations USING gin (to_tsvector('english', value));

-- ===========================================================================
-- AUDIT LOGS (partitioned)
-- ===========================================================================
CREATE INDEX idx_audit_logs_tenant_action
    ON audit_logs (tenant_id, action, occurred_at DESC);

CREATE INDEX idx_audit_logs_user
    ON audit_logs (user_id, occurred_at DESC)
    WHERE user_id IS NOT NULL;

CREATE INDEX idx_audit_logs_resource
    ON audit_logs (tenant_id, resource_type, resource_id)
    WHERE resource_id IS NOT NULL;

-- ===========================================================================
-- SECURITY EVENTS
-- ===========================================================================
CREATE INDEX idx_security_events_tenant_severity
    ON security_events (tenant_id, severity, occurred_at DESC)
    WHERE resolved = FALSE;

CREATE INDEX idx_security_events_user
    ON security_events (user_id, occurred_at DESC)
    WHERE user_id IS NOT NULL;

CREATE INDEX idx_security_events_ip
    ON security_events (ip_address, occurred_at DESC)
    WHERE ip_address IS NOT NULL;

-- ===========================================================================
-- USER CONSENTS
-- ===========================================================================
CREATE INDEX idx_user_consents_user_type
    ON user_consents (user_id, consent_type, status);

CREATE INDEX idx_user_consents_tenant
    ON user_consents (tenant_id, consent_type, status);

-- ===========================================================================
-- PII DELETION REQUESTS
-- ===========================================================================
CREATE INDEX idx_pii_deletion_requests_status
    ON pii_deletion_requests (status, scheduled_for)
    WHERE status IN ('requested','in_progress');

CREATE INDEX idx_pii_deletion_requests_user
    ON pii_deletion_requests (user_id, status);

-- ===========================================================================
-- PASSWORD RESET & MAGIC LINKS
-- ===========================================================================
CREATE INDEX idx_password_reset_tokens_hash
    ON password_reset_tokens (token_hash);

CREATE INDEX idx_password_reset_tokens_user
    ON password_reset_tokens (user_id, used, expires_at);

CREATE INDEX idx_magic_links_hash
    ON magic_links (token_hash);

-- ===========================================================================
-- EMAIL VERIFICATION
-- ===========================================================================
CREATE INDEX idx_email_verification_tokens_hash
    ON email_verification_tokens (token_hash);

CREATE INDEX idx_email_verification_tokens_user
    ON email_verification_tokens (user_id, used, expires_at);

-- ===========================================================================
-- IP LISTS
-- ===========================================================================
CREATE INDEX idx_ip_allowlist_tenant
    ON ip_allowlist (tenant_id)
    WHERE is_active = TRUE;

CREATE INDEX idx_ip_blocklist_tenant
    ON ip_blocklist (tenant_id);

-- Partial index: non-expired blocks
CREATE INDEX idx_ip_blocklist_active
    ON ip_blocklist (tenant_id, cidr)
    WHERE expires_at IS NULL OR expires_at > now();

-- ===========================================================================
-- WEBHOOKS
-- ===========================================================================
CREATE INDEX idx_webhooks_tenant_active
    ON webhooks (tenant_id, is_active)
    WHERE is_active = TRUE;

CREATE INDEX idx_webhook_deliveries_webhook
    ON webhook_deliveries (webhook_id, created_at DESC);

CREATE INDEX idx_webhook_deliveries_tenant
    ON webhook_deliveries (tenant_id, created_at DESC);
