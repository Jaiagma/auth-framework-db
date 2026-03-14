-- ============================================================
-- enums.sql
-- PostgreSQL ENUM type definitions for the multi-tenant
-- authentication framework.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- Tenant / Application
-- ────────────────────────────────────────────────────────────
CREATE TYPE tenant_status AS ENUM (
    'active',
    'suspended',
    'pending',
    'deleted'
);

CREATE TYPE application_type AS ENUM (
    'web',
    'mobile',
    'spa',           -- Single-Page Application
    'native',
    'service',       -- Machine-to-machine / API client
    'browser_ext'    -- Browser extension
);

-- ────────────────────────────────────────────────────────────
-- Users & Credentials
-- ────────────────────────────────────────────────────────────
CREATE TYPE user_status AS ENUM (
    'active',
    'inactive',
    'locked',
    'pending_verification',
    'suspended',
    'deleted'
);

CREATE TYPE credential_type AS ENUM (
    'password',
    'passkey',      -- WebAuthn passkey
    'magic_link',
    'certificate'
);

CREATE TYPE user_role_type AS ENUM (
    'super_admin',
    'tenant_admin',
    'app_admin',
    'user',
    'guest',
    'service_account',
    'read_only'
);

-- ────────────────────────────────────────────────────────────
-- MFA
-- ────────────────────────────────────────────────────────────
CREATE TYPE mfa_method_type AS ENUM (
    'totp',      -- Time-based One-Time Password (RFC 6238)
    'sms',
    'email',
    'webauthn',  -- FIDO2 / WebAuthn
    'push',      -- Push notification (Duo, Okta Verify, etc.)
    'backup_code'
);

CREATE TYPE mfa_device_status AS ENUM (
    'active',
    'inactive',
    'revoked',
    'pending_activation'
);

-- ────────────────────────────────────────────────────────────
-- Sessions
-- ────────────────────────────────────────────────────────────
CREATE TYPE session_status AS ENUM (
    'active',
    'expired',
    'revoked',
    'logged_out'
);

-- ────────────────────────────────────────────────────────────
-- OAuth 2.0
-- ────────────────────────────────────────────────────────────
CREATE TYPE oauth_grant_type AS ENUM (
    'authorization_code',
    'client_credentials',
    'refresh_token',
    'device_code',
    'implicit',           -- Legacy – included for compatibility
    'password'            -- Legacy – included for compatibility
);

CREATE TYPE oauth_token_type AS ENUM (
    'access_token',
    'refresh_token',
    'id_token'
);

CREATE TYPE oauth_token_status AS ENUM (
    'active',
    'expired',
    'revoked'
);

CREATE TYPE oauth_response_type AS ENUM (
    'code',
    'token',
    'id_token',
    'code token',
    'code id_token',
    'token id_token',
    'code token id_token'
);

-- Standard OAuth 2.0 + OpenID Connect scopes
CREATE TYPE oauth_scope_type AS ENUM (
    'openid',
    'profile',
    'email',
    'phone',
    'address',
    'offline_access',
    'read',
    'write',
    'admin',
    'api',
    'mfa',
    'impersonation'
);

-- ────────────────────────────────────────────────────────────
-- Identity Providers (IdP)
-- ────────────────────────────────────────────────────────────
CREATE TYPE idp_type AS ENUM (
    'saml2',
    'oidc',
    'oauth2',
    'ldap',
    'active_directory',
    'google',
    'github',
    'microsoft',
    'apple',
    'facebook',
    'twitter',
    'linkedin',
    'auth0',
    'okta',
    'onelogin',
    'pingidentity',
    'custom'
);

CREATE TYPE idp_status AS ENUM (
    'active',
    'inactive',
    'testing',
    'deprecated'
);

CREATE TYPE federated_identity_status AS ENUM (
    'active',
    'unlinked',
    'suspended'
);

-- ────────────────────────────────────────────────────────────
-- SSO
-- ────────────────────────────────────────────────────────────
CREATE TYPE sso_protocol AS ENUM (
    'saml2',
    'oidc',
    'wsfed'    -- WS-Federation
);

CREATE TYPE sso_session_status AS ENUM (
    'active',
    'expired',
    'logged_out'
);

-- ────────────────────────────────────────────────────────────
-- Audit & Compliance
-- ────────────────────────────────────────────────────────────
CREATE TYPE audit_event_type AS ENUM (
    -- Authentication
    'login_success',
    'login_failure',
    'logout',
    'session_expired',
    'session_revoked',
    -- MFA
    'mfa_enrolled',
    'mfa_verified',
    'mfa_failed',
    'mfa_revoked',
    'recovery_code_used',
    -- Account lifecycle
    'user_created',
    'user_updated',
    'user_deleted',
    'user_suspended',
    'user_activated',
    'password_changed',
    'password_reset_requested',
    'email_verified',
    -- OAuth / Tokens
    'token_issued',
    'token_refreshed',
    'token_revoked',
    'authorization_granted',
    'authorization_denied',
    -- SSO / Federation
    'sso_login',
    'sso_logout',
    'idp_linked',
    'idp_unlinked',
    -- Administration
    'tenant_created',
    'tenant_updated',
    'role_assigned',
    'role_revoked',
    'permission_granted',
    'permission_revoked',
    -- Compliance
    'consent_given',
    'consent_withdrawn',
    'data_export_requested',
    'data_deletion_requested',
    'data_deleted',
    -- Security
    'suspicious_activity',
    'rate_limit_exceeded',
    'ip_blocked',
    'brute_force_detected',
    'api_key_created',
    'api_key_revoked'
);

CREATE TYPE audit_severity AS ENUM (
    'info',
    'warning',
    'error',
    'critical'
);

-- ────────────────────────────────────────────────────────────
-- Consent & GDPR
-- ────────────────────────────────────────────────────────────
CREATE TYPE consent_type AS ENUM (
    'terms_of_service',
    'privacy_policy',
    'cookie_policy',
    'marketing_emails',
    'analytics',
    'data_processing',
    'data_sharing',
    'third_party_integrations',
    'biometric_data',
    'geolocation'
);

CREATE TYPE consent_status AS ENUM (
    'granted',
    'withdrawn',
    'expired',
    'pending'
);

CREATE TYPE deletion_request_status AS ENUM (
    'pending',
    'in_progress',
    'completed',
    'failed',
    'cancelled'
);

-- ────────────────────────────────────────────────────────────
-- PII & Data Classification
-- ────────────────────────────────────────────────────────────
CREATE TYPE pii_classification AS ENUM (
    'public',
    'internal',
    'confidential',
    'restricted',   -- e.g., passwords, MFA secrets
    'sensitive_pii', -- GDPR special categories, US regulated PII
    'financial',
    'health'
);

CREATE TYPE pii_regulation AS ENUM (
    'gdpr',       -- EU General Data Protection Regulation
    'ccpa',       -- California Consumer Privacy Act
    'hipaa',      -- US Health Insurance Portability and Accountability Act
    'coppa',      -- Children's Online Privacy Protection Act
    'pipeda',     -- Canada
    'lgpd',       -- Brazil
    'pdpa',       -- Thailand / Singapore
    'eidas',      -- EU electronic identification
    'ferpa',      -- US Family Educational Rights and Privacy Act
    'glba'        -- US Gramm–Leach–Bliley Act
);

-- ────────────────────────────────────────────────────────────
-- Security
-- ────────────────────────────────────────────────────────────
CREATE TYPE risk_level AS ENUM (
    'low',
    'medium',
    'high',
    'critical'
);

CREATE TYPE security_event_type AS ENUM (
    'brute_force',
    'credential_stuffing',
    'account_takeover',
    'bot_activity',
    'impossible_travel',
    'new_device',
    'new_location',
    'leaked_credential',
    'suspicious_ip',
    'anomalous_behavior',
    'privilege_escalation'
);

CREATE TYPE security_event_status AS ENUM (
    'open',
    'investigating',
    'mitigated',
    'resolved',
    'false_positive'
);

CREATE TYPE device_trust_level AS ENUM (
    'unknown',
    'unverified',
    'verified',
    'managed'
);

-- ────────────────────────────────────────────────────────────
-- Regional / Localization
-- ────────────────────────────────────────────────────────────
CREATE TYPE data_residency_region AS ENUM (
    'us',
    'eu',
    'uk',
    'ca',
    'au',
    'ap',
    'global'
);

CREATE TYPE regulation_region AS ENUM (
    'eu',
    'us',
    'us_california',
    'us_virginia',
    'uk',
    'canada',
    'brazil',
    'australia',
    'india',
    'singapore',
    'japan',
    'global'
);
