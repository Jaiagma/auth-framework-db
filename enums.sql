-- =============================================================================
-- enums.sql
-- PostgreSQL ENUM type definitions for the multi-tenant auth framework
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Tenant & Organisation
-- ---------------------------------------------------------------------------
CREATE TYPE tenant_status AS ENUM (
    'active',
    'suspended',
    'pending_activation',
    'deactivated',
    'deleted'
);

CREATE TYPE tenant_plan AS ENUM (
    'free',
    'starter',
    'professional',
    'enterprise',
    'custom'
);

-- ---------------------------------------------------------------------------
-- User & Account
-- ---------------------------------------------------------------------------
CREATE TYPE user_status AS ENUM (
    'active',
    'inactive',
    'suspended',
    'pending_verification',
    'locked',
    'deleted'
);

CREATE TYPE user_role AS ENUM (
    'super_admin',
    'tenant_admin',
    'developer',
    'end_user',
    'service_account',
    'guest'
);

-- ---------------------------------------------------------------------------
-- Authentication
-- ---------------------------------------------------------------------------
CREATE TYPE auth_method AS ENUM (
    'password',
    'magic_link',
    'passkey',
    'sso',
    'oauth',
    'api_key',
    'certificate'
);

CREATE TYPE mfa_method AS ENUM (
    'totp',
    'sms',
    'email',
    'webauthn',
    'push',
    'backup_code',
    'hardware_key'
);

CREATE TYPE mfa_status AS ENUM (
    'pending',
    'active',
    'disabled',
    'revoked'
);

-- ---------------------------------------------------------------------------
-- Sessions
-- ---------------------------------------------------------------------------
CREATE TYPE session_status AS ENUM (
    'active',
    'expired',
    'revoked',
    'logged_out'
);

-- ---------------------------------------------------------------------------
-- OAuth 2.0 / OIDC
-- ---------------------------------------------------------------------------
CREATE TYPE oauth_grant_type AS ENUM (
    'authorization_code',
    'client_credentials',
    'refresh_token',
    'implicit',
    'device_code',
    'jwt_bearer'
);

CREATE TYPE oauth_token_type AS ENUM (
    'access_token',
    'refresh_token',
    'id_token',
    'device_code',
    'authorization_code'
);

CREATE TYPE oauth_token_status AS ENUM (
    'active',
    'expired',
    'revoked',
    'consumed'
);

CREATE TYPE oauth_client_type AS ENUM (
    'confidential',
    'public'
);

-- ---------------------------------------------------------------------------
-- Identity Providers (IdP)
-- ---------------------------------------------------------------------------
CREATE TYPE idp_provider_type AS ENUM (
    'google',
    'github',
    'microsoft',
    'auth0',
    'okta',
    'facebook',
    'twitter',
    'apple',
    'linkedin',
    'slack',
    'salesforce',
    'custom_oidc',
    'custom_saml',
    'ldap',
    'active_directory'
);

CREATE TYPE idp_protocol AS ENUM (
    'oidc',
    'saml2',
    'oauth2',
    'ldap',
    'ws_federation',
    'cas'
);

CREATE TYPE idp_status AS ENUM (
    'active',
    'disabled',
    'pending_configuration',
    'error'
);

-- ---------------------------------------------------------------------------
-- SSO
-- ---------------------------------------------------------------------------
CREATE TYPE sso_session_status AS ENUM (
    'active',
    'expired',
    'terminated'
);

CREATE TYPE saml_binding AS ENUM (
    'http_post',
    'http_redirect',
    'http_artifact',
    'soap'
);

-- ---------------------------------------------------------------------------
-- Security Events & Audit
-- ---------------------------------------------------------------------------
CREATE TYPE audit_action AS ENUM (
    'user_created',
    'user_updated',
    'user_deleted',
    'user_login',
    'user_logout',
    'user_locked',
    'user_unlocked',
    'password_changed',
    'password_reset_requested',
    'password_reset_completed',
    'mfa_enrolled',
    'mfa_verified',
    'mfa_disabled',
    'mfa_recovery_used',
    'oauth_token_issued',
    'oauth_token_revoked',
    'oauth_authorization_granted',
    'oauth_authorization_revoked',
    'sso_session_started',
    'sso_session_ended',
    'idp_linked',
    'idp_unlinked',
    'tenant_created',
    'tenant_updated',
    'tenant_deleted',
    'api_key_created',
    'api_key_revoked',
    'role_assigned',
    'role_revoked',
    'consent_given',
    'consent_revoked',
    'data_export_requested',
    'data_deletion_requested',
    'data_deleted',
    'policy_updated',
    'config_changed',
    'security_alert',
    'suspicious_activity',
    'brute_force_detected',
    'ip_blocked',
    'device_trusted',
    'device_revoked'
);

CREATE TYPE security_event_severity AS ENUM (
    'info',
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TYPE security_event_type AS ENUM (
    'login_failure',
    'brute_force',
    'credential_stuffing',
    'account_takeover',
    'suspicious_location',
    'impossible_travel',
    'device_anomaly',
    'token_abuse',
    'privilege_escalation',
    'data_exfiltration',
    'policy_violation',
    'anomalous_behavior'
);

-- ---------------------------------------------------------------------------
-- Compliance & GDPR
-- ---------------------------------------------------------------------------
CREATE TYPE consent_type AS ENUM (
    'terms_of_service',
    'privacy_policy',
    'marketing_emails',
    'analytics_tracking',
    'data_sharing',
    'cookie_consent',
    'data_processing',
    'cross_border_transfer'
);

CREATE TYPE consent_status AS ENUM (
    'given',
    'withdrawn',
    'pending',
    'expired'
);

CREATE TYPE data_deletion_status AS ENUM (
    'requested',
    'in_progress',
    'completed',
    'failed',
    'cancelled'
);

CREATE TYPE data_classification AS ENUM (
    'public',
    'internal',
    'confidential',
    'restricted',
    'pii',
    'sensitive_pii',
    'phi',
    'financial'
);

CREATE TYPE retention_policy_type AS ENUM (
    'delete',
    'anonymize',
    'archive',
    'retain'
);

CREATE TYPE regulation_type AS ENUM (
    'gdpr',
    'ccpa',
    'hipaa',
    'pci_dss',
    'sox',
    'eidas',
    'lgpd',
    'pipeda',
    'pdpa',
    'appi'
);

-- ---------------------------------------------------------------------------
-- Device & Geolocation
-- ---------------------------------------------------------------------------
CREATE TYPE device_type AS ENUM (
    'desktop',
    'mobile',
    'tablet',
    'smart_tv',
    'iot',
    'unknown'
);

CREATE TYPE device_trust_status AS ENUM (
    'trusted',
    'untrusted',
    'pending_verification',
    'revoked'
);

-- ---------------------------------------------------------------------------
-- API Keys
-- ---------------------------------------------------------------------------
CREATE TYPE api_key_status AS ENUM (
    'active',
    'revoked',
    'expired'
);

-- ---------------------------------------------------------------------------
-- Password / Credential
-- ---------------------------------------------------------------------------
CREATE TYPE password_hash_algorithm AS ENUM (
    'argon2id',
    'bcrypt',
    'scrypt',
    'pbkdf2'
);
