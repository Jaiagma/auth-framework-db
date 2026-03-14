-- =============================================================================
-- migrations/001_initial_schema.sql
-- Initial migration: Multi-Tenant Authentication Framework
-- UUID v7 for all primary and foreign keys
--
-- Apply order:
--   1. extensions.sql
--   2. enums.sql
--   3. functions.sql  (uuid_generate_v7 must exist before schema.sql)
--   4. schema.sql
--   5. triggers.sql
--   6. indexes.sql
--   7. views.sql
--   8. rls_policies.sql
--   9. seed_data.sql
--
-- This single migration file bundles all steps for initial deployment.
-- Run with: psql -d <database> -f migrations/001_initial_schema.sql
-- =============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- Migration metadata table (idempotent)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_migrations (
    version     TEXT        PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    description TEXT
);

-- Guard: skip if already applied
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM schema_migrations WHERE version = '001'
    ) THEN
        RAISE NOTICE 'Migration 001 already applied – skipping.';
        -- Signal rollback-without-error to exit early
        RAISE EXCEPTION 'ALREADY_APPLIED' USING ERRCODE = 'P0001';
    END IF;
END
$$;

-- ===========================================================================
-- STEP 1 – EXTENSIONS
-- ===========================================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- ===========================================================================
-- STEP 2 – ENUM TYPES
-- ===========================================================================

CREATE TYPE tenant_status AS ENUM (
    'active','suspended','pending_activation','deactivated','deleted'
);
CREATE TYPE tenant_plan AS ENUM (
    'free','starter','professional','enterprise','custom'
);
CREATE TYPE user_status AS ENUM (
    'active','inactive','suspended','pending_verification','locked','deleted'
);
CREATE TYPE user_role AS ENUM (
    'super_admin','tenant_admin','developer','end_user','service_account','guest'
);
CREATE TYPE auth_method AS ENUM (
    'password','magic_link','passkey','sso','oauth','api_key','certificate'
);
CREATE TYPE mfa_method AS ENUM (
    'totp','sms','email','webauthn','push','backup_code','hardware_key'
);
CREATE TYPE mfa_status AS ENUM (
    'pending','active','disabled','revoked'
);
CREATE TYPE session_status AS ENUM (
    'active','expired','revoked','logged_out'
);
CREATE TYPE oauth_grant_type AS ENUM (
    'authorization_code','client_credentials','refresh_token',
    'implicit','device_code','jwt_bearer'
);
CREATE TYPE oauth_token_type AS ENUM (
    'access_token','refresh_token','id_token','device_code','authorization_code'
);
CREATE TYPE oauth_token_status AS ENUM (
    'active','expired','revoked','consumed'
);
CREATE TYPE oauth_client_type AS ENUM (
    'confidential','public'
);
CREATE TYPE idp_provider_type AS ENUM (
    'google','github','microsoft','auth0','okta','facebook','twitter','apple',
    'linkedin','slack','salesforce','custom_oidc','custom_saml','ldap','active_directory'
);
CREATE TYPE idp_protocol AS ENUM (
    'oidc','saml2','oauth2','ldap','ws_federation','cas'
);
CREATE TYPE idp_status AS ENUM (
    'active','disabled','pending_configuration','error'
);
CREATE TYPE sso_session_status AS ENUM (
    'active','expired','terminated'
);
CREATE TYPE saml_binding AS ENUM (
    'http_post','http_redirect','http_artifact','soap'
);
CREATE TYPE audit_action AS ENUM (
    'user_created','user_updated','user_deleted',
    'user_login','user_logout','user_locked','user_unlocked',
    'password_changed','password_reset_requested','password_reset_completed',
    'mfa_enrolled','mfa_verified','mfa_disabled','mfa_recovery_used',
    'oauth_token_issued','oauth_token_revoked',
    'oauth_authorization_granted','oauth_authorization_revoked',
    'sso_session_started','sso_session_ended',
    'idp_linked','idp_unlinked',
    'tenant_created','tenant_updated','tenant_deleted',
    'api_key_created','api_key_revoked',
    'role_assigned','role_revoked',
    'consent_given','consent_revoked',
    'data_export_requested','data_deletion_requested','data_deleted',
    'policy_updated','config_changed',
    'security_alert','suspicious_activity','brute_force_detected',
    'ip_blocked','device_trusted','device_revoked'
);
CREATE TYPE security_event_severity AS ENUM (
    'info','low','medium','high','critical'
);
CREATE TYPE security_event_type AS ENUM (
    'login_failure','brute_force','credential_stuffing','account_takeover',
    'suspicious_location','impossible_travel','device_anomaly','token_abuse',
    'privilege_escalation','data_exfiltration','policy_violation','anomalous_behavior'
);
CREATE TYPE consent_type AS ENUM (
    'terms_of_service','privacy_policy','marketing_emails','analytics_tracking',
    'data_sharing','cookie_consent','data_processing','cross_border_transfer'
);
CREATE TYPE consent_status AS ENUM (
    'given','withdrawn','pending','expired'
);
CREATE TYPE data_deletion_status AS ENUM (
    'requested','in_progress','completed','failed','cancelled'
);
CREATE TYPE data_classification AS ENUM (
    'public','internal','confidential','restricted','pii','sensitive_pii','phi','financial'
);
CREATE TYPE retention_policy_type AS ENUM (
    'delete','anonymize','archive','retain'
);
CREATE TYPE regulation_type AS ENUM (
    'gdpr','ccpa','hipaa','pci_dss','sox','eidas','lgpd','pipeda','pdpa','appi'
);
CREATE TYPE device_type AS ENUM (
    'desktop','mobile','tablet','smart_tv','iot','unknown'
);
CREATE TYPE device_trust_status AS ENUM (
    'trusted','untrusted','pending_verification','revoked'
);
CREATE TYPE api_key_status AS ENUM (
    'active','revoked','expired'
);
CREATE TYPE password_hash_algorithm AS ENUM (
    'argon2id','bcrypt','scrypt','pbkdf2'
);

-- ===========================================================================
-- STEP 3 – UUID v7 FUNCTION
-- ===========================================================================
CREATE OR REPLACE FUNCTION uuid_generate_v7()
RETURNS UUID
LANGUAGE plpgsql
PARALLEL SAFE
AS $$
DECLARE
    v_unix_ms BIGINT;
    v_rand    BYTEA;
    v_hex     TEXT;
BEGIN
    v_unix_ms := (EXTRACT(EPOCH FROM clock_timestamp()) * 1000)::BIGINT;
    v_rand    := gen_random_bytes(10);
    v_hex :=
        lpad(to_hex(v_unix_ms), 12, '0') ||
        '7' ||
        lpad(to_hex((get_byte(v_rand, 0) & 15)), 1, '0') ||
        lpad(to_hex(get_byte(v_rand, 1)), 2, '0') ||
        lpad(to_hex((get_byte(v_rand, 2) & 63) | 128), 2, '0') ||
        encode(substring(v_rand from 4 for 6), 'hex');
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

CREATE OR REPLACE FUNCTION uuid_v7_to_timestamptz(p_uuid UUID)
RETURNS TIMESTAMPTZ
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT to_timestamp(
        ('x' || lpad(replace(p_uuid::TEXT, '-', ''), 12, '0'))::BIT(48)::BIGINT / 1000.0
    );
$$;

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;

-- ===========================================================================
-- STEP 4 – CORE SCHEMA TABLES
-- ===========================================================================

-- Tenants
CREATE TABLE tenants (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    name                    TEXT NOT NULL,
    slug                    TEXT NOT NULL UNIQUE,
    display_name            TEXT,
    description             TEXT,
    status                  tenant_status NOT NULL DEFAULT 'pending_activation',
    plan                    tenant_plan   NOT NULL DEFAULT 'free',
    logo_url                TEXT,
    primary_color           VARCHAR(7),
    login_url               TEXT,
    support_email           TEXT,
    billing_email           TEXT,
    default_language        VARCHAR(10)  NOT NULL DEFAULT 'en',
    default_timezone        TEXT         NOT NULL DEFAULT 'UTC',
    default_region          VARCHAR(10),
    security_settings       JSONB        NOT NULL DEFAULT '{}',
    max_users               INT,
    max_applications        INT          DEFAULT 10,
    max_api_keys            INT          DEFAULT 50,
    data_residency_region   TEXT,
    applicable_regulations  regulation_type[] DEFAULT '{}',
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at              TIMESTAMPTZ
);

CREATE TABLE tenant_domains (
    id          UUID  PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    domain      TEXT  NOT NULL UNIQUE,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
    verified    BOOLEAN NOT NULL DEFAULT FALSE,
    verified_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users
CREATE TABLE users (
    id                          UUID    PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id                   UUID    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email_encrypted             BYTEA   NOT NULL,
    email_hash                  TEXT    NOT NULL,
    phone_encrypted             BYTEA,
    phone_hash                  TEXT,
    first_name_encrypted        BYTEA,
    last_name_encrypted         BYTEA,
    display_name                TEXT,
    avatar_url                  TEXT,
    status                      user_status  NOT NULL DEFAULT 'pending_verification',
    role                        user_role    NOT NULL DEFAULT 'end_user',
    email_verified              BOOLEAN      NOT NULL DEFAULT FALSE,
    email_verified_at           TIMESTAMPTZ,
    phone_verified              BOOLEAN      NOT NULL DEFAULT FALSE,
    phone_verified_at           TIMESTAMPTZ,
    language_code               VARCHAR(10)  NOT NULL DEFAULT 'en',
    timezone                    TEXT         NOT NULL DEFAULT 'UTC',
    failed_login_attempts       INT          NOT NULL DEFAULT 0,
    locked_until                TIMESTAMPTZ,
    last_login_at               TIMESTAMPTZ,
    last_login_ip               INET,
    password_changed_at         TIMESTAMPTZ,
    must_change_password        BOOLEAN      NOT NULL DEFAULT FALSE,
    gdpr_consent_given          BOOLEAN      NOT NULL DEFAULT FALSE,
    gdpr_consent_given_at       TIMESTAMPTZ,
    data_deletion_requested_at  TIMESTAMPTZ,
    external_id                 TEXT,
    metadata                    JSONB        NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at                  TIMESTAMPTZ,
    UNIQUE (tenant_id, email_hash)
);

CREATE TABLE user_passwords (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    password_hash   TEXT NOT NULL,
    algorithm       password_hash_algorithm NOT NULL DEFAULT 'argon2id',
    salt            TEXT,
    iterations      INT,
    is_current      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ
);

CREATE TABLE user_roles (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        user_role NOT NULL,
    granted_by  UUID REFERENCES users(id),
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ,
    UNIQUE (tenant_id, user_id, role)
);

-- Applications
CREATE TABLE applications (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                TEXT NOT NULL,
    slug                TEXT NOT NULL,
    description         TEXT,
    logo_url            TEXT,
    client_id           TEXT NOT NULL UNIQUE DEFAULT gen_random_uuid()::TEXT,
    client_secret_hash  TEXT,
    client_type         oauth_client_type NOT NULL DEFAULT 'confidential',
    redirect_uris       JSONB NOT NULL DEFAULT '[]',
    post_logout_uris    JSONB NOT NULL DEFAULT '[]',
    allowed_origins     JSONB NOT NULL DEFAULT '[]',
    allowed_grant_types oauth_grant_type[] NOT NULL DEFAULT '{authorization_code}',
    access_token_ttl    INT  NOT NULL DEFAULT 3600,
    refresh_token_ttl   INT  NOT NULL DEFAULT 2592000,
    id_token_ttl        INT  NOT NULL DEFAULT 3600,
    require_pkce        BOOLEAN NOT NULL DEFAULT TRUE,
    is_first_party      BOOLEAN NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    metadata            JSONB NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, slug)
);

-- MFA
CREATE TABLE mfa_devices (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    method          mfa_method NOT NULL,
    status          mfa_status NOT NULL DEFAULT 'pending',
    name            TEXT,
    secret_encrypted BYTEA,
    credential_id   TEXT,
    public_key      TEXT,
    sign_count      BIGINT,
    aaguid          TEXT,
    delivery_address_encrypted BYTEA,
    push_token_encrypted BYTEA,
    device_platform TEXT,
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_recovery_codes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    code_hash   TEXT NOT NULL,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_challenges (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id       UUID REFERENCES mfa_devices(id),
    method          mfa_method NOT NULL,
    challenge_data  JSONB NOT NULL DEFAULT '{}',
    verified        BOOLEAN NOT NULL DEFAULT FALSE,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Sessions
CREATE TABLE sessions (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID REFERENCES applications(id),
    status              session_status NOT NULL DEFAULT 'active',
    session_token_hash  TEXT NOT NULL UNIQUE,
    refresh_token_hash  TEXT UNIQUE,
    auth_methods        auth_method[] NOT NULL DEFAULT '{}',
    mfa_verified        BOOLEAN NOT NULL DEFAULT FALSE,
    mfa_device_id       UUID REFERENCES mfa_devices(id),
    ip_address          INET,
    user_agent          TEXT,
    device_id           UUID,
    country_code        VARCHAR(2),
    region              TEXT,
    city                TEXT,
    last_activity_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

-- Devices
CREATE TABLE devices (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_type         device_type NOT NULL DEFAULT 'unknown',
    trust_status        device_trust_status NOT NULL DEFAULT 'untrusted',
    fingerprint_hash    TEXT NOT NULL,
    user_agent          TEXT,
    browser             TEXT,
    browser_version     TEXT,
    os                  TEXT,
    os_version          TEXT,
    last_ip             INET,
    friendly_name       TEXT,
    trust_token_hash    TEXT,
    trusted_at          TIMESTAMPTZ,
    trusted_until       TIMESTAMPTZ,
    last_seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

ALTER TABLE sessions
    ADD CONSTRAINT fk_sessions_device
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL;

-- OAuth 2.0
CREATE TABLE oauth_scopes (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    description TEXT,
    is_default  BOOLEAN NOT NULL DEFAULT FALSE,
    is_public   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE application_scopes (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    application_id  UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    scope_id        UUID NOT NULL REFERENCES oauth_scopes(id) ON DELETE CASCADE,
    UNIQUE (application_id, scope_id)
);

CREATE TABLE oauth_authorization_codes (
    id                    UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id             UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id        UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash             TEXT NOT NULL UNIQUE,
    scopes                TEXT[] NOT NULL DEFAULT '{}',
    redirect_uri          TEXT NOT NULL,
    code_challenge        TEXT,
    code_challenge_method TEXT,
    nonce                 TEXT,
    state                 TEXT,
    used                  BOOLEAN NOT NULL DEFAULT FALSE,
    used_at               TIMESTAMPTZ,
    expires_at            TIMESTAMPTZ NOT NULL,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oauth_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE CASCADE,
    session_id      UUID REFERENCES sessions(id) ON DELETE CASCADE,
    token_type      oauth_token_type   NOT NULL,
    token_hash      TEXT               NOT NULL UNIQUE,
    scopes          TEXT[]             NOT NULL DEFAULT '{}',
    grant_type      oauth_grant_type   NOT NULL,
    status          oauth_token_status NOT NULL DEFAULT 'active',
    claims          JSONB              NOT NULL DEFAULT '{}',
    expires_at      TIMESTAMPTZ        NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ        NOT NULL DEFAULT now()
);

CREATE TABLE oauth_refresh_tokens (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    access_token_id UUID NOT NULL REFERENCES oauth_tokens(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash      TEXT NOT NULL UNIQUE,
    rotation_count  INT  NOT NULL DEFAULT 0,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- API Keys
CREATE TABLE api_keys (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID REFERENCES applications(id) ON DELETE CASCADE,
    created_by      UUID NOT NULL REFERENCES users(id),
    name            TEXT NOT NULL,
    key_prefix      VARCHAR(10) NOT NULL,
    key_hash        TEXT        NOT NULL UNIQUE,
    scopes          TEXT[]      NOT NULL DEFAULT '{}',
    status          api_key_status NOT NULL DEFAULT 'active',
    last_used_at    TIMESTAMPTZ,
    last_used_ip    INET,
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at      TIMESTAMPTZ
);

-- Identity Providers
CREATE TABLE identity_providers (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id            UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                 TEXT NOT NULL,
    display_name         TEXT,
    logo_url             TEXT,
    provider_type        idp_provider_type NOT NULL,
    protocol             idp_protocol      NOT NULL,
    status               idp_status        NOT NULL DEFAULT 'pending_configuration',
    config_encrypted     BYTEA,
    attribute_mapping    JSONB             NOT NULL DEFAULT '{}',
    auto_provision_users BOOLEAN           NOT NULL DEFAULT FALSE,
    default_role         user_role         NOT NULL DEFAULT 'end_user',
    display_order        INT               NOT NULL DEFAULT 0,
    is_default           BOOLEAN           NOT NULL DEFAULT FALSE,
    created_at           TIMESTAMPTZ       NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ       NOT NULL DEFAULT now()
);

CREATE TABLE oidc_configurations (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    provider_id             UUID NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE UNIQUE,
    tenant_id               UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    issuer_url              TEXT NOT NULL,
    authorization_endpoint  TEXT NOT NULL,
    token_endpoint          TEXT NOT NULL,
    userinfo_endpoint       TEXT,
    jwks_uri                TEXT NOT NULL,
    end_session_endpoint    TEXT,
    client_id               TEXT NOT NULL,
    client_secret_encrypted BYTEA,
    scopes                  TEXT[] NOT NULL DEFAULT '{openid,profile,email}',
    response_type           TEXT   NOT NULL DEFAULT 'code',
    pkce_required           BOOLEAN NOT NULL DEFAULT TRUE,
    discovery_document      JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE saml_configurations (
    id                       UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    provider_id              UUID NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE UNIQUE,
    tenant_id                UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    sp_entity_id             TEXT NOT NULL,
    sp_acs_url               TEXT NOT NULL,
    sp_slo_url               TEXT,
    sp_certificate           TEXT,
    sp_private_key_encrypted BYTEA,
    idp_entity_id            TEXT NOT NULL,
    idp_sso_url              TEXT NOT NULL,
    idp_slo_url              TEXT,
    idp_certificate          TEXT NOT NULL,
    name_id_format           TEXT NOT NULL DEFAULT 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
    sign_requests            BOOLEAN NOT NULL DEFAULT TRUE,
    sign_assertions          BOOLEAN NOT NULL DEFAULT TRUE,
    encrypt_assertions       BOOLEAN NOT NULL DEFAULT FALSE,
    default_relay_state      TEXT,
    binding                  saml_binding NOT NULL DEFAULT 'http_post',
    idp_metadata_xml         TEXT,
    created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Federated Identities
CREATE TABLE federated_identities (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id                 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id               UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    provider_id             UUID NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    external_subject        TEXT NOT NULL,
    external_email_hash     TEXT,
    access_token_encrypted  BYTEA,
    refresh_token_encrypted BYTEA,
    id_token_encrypted      BYTEA,
    token_expires_at        TIMESTAMPTZ,
    raw_profile             JSONB NOT NULL DEFAULT '{}',
    first_linked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, provider_id, external_subject)
);

-- SSO Sessions
CREATE TABLE sso_sessions (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id     UUID NOT NULL REFERENCES identity_providers(id),
    idp_session_id  TEXT,
    status          sso_session_status NOT NULL DEFAULT 'active',
    session_index   TEXT,
    authn_context   TEXT,
    ip_address      INET,
    user_agent      TEXT,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    terminated_at   TIMESTAMPTZ
);

CREATE TABLE sso_session_applications (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    sso_session_id  UUID NOT NULL REFERENCES sso_sessions(id) ON DELETE CASCADE,
    application_id  UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    session_id      UUID REFERENCES sessions(id),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sso_session_id, application_id)
);

-- Localization
CREATE TABLE languages (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    code        VARCHAR(10) NOT NULL UNIQUE,
    name        TEXT NOT NULL,
    native_name TEXT NOT NULL,
    direction   VARCHAR(3)  NOT NULL DEFAULT 'ltr' CHECK (direction IN ('ltr','rtl')),
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE timezones (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    name            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    offset_seconds  INT  NOT NULL DEFAULT 0,
    region          TEXT,
    is_dst          BOOLEAN NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_localization_preferences (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    language_id     UUID REFERENCES languages(id),
    timezone_id     UUID REFERENCES timezones(id),
    locale          VARCHAR(20),
    date_format     TEXT NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format     TEXT NOT NULL DEFAULT 'HH:mm:ss',
    currency_code   VARCHAR(3),
    number_format   TEXT NOT NULL DEFAULT 'en-US',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenant_regional_settings (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id               UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    region_code             VARCHAR(10) NOT NULL,
    applicable_regulations  regulation_type[] NOT NULL DEFAULT '{}',
    data_residency_zone     TEXT,
    allowed_auth_methods    auth_method[] NOT NULL DEFAULT '{}',
    require_mfa             BOOLEAN NOT NULL DEFAULT FALSE,
    default_language_id     UUID REFERENCES languages(id),
    default_timezone_id     UUID REFERENCES timezones(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, region_code)
);

CREATE TABLE ui_translations (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
    language_id UUID NOT NULL REFERENCES languages(id),
    key         TEXT NOT NULL,
    value       TEXT NOT NULL,
    namespace   TEXT NOT NULL DEFAULT 'auth',
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, language_id, namespace, key)
);

-- Audit Logs (partitioned by month)
CREATE TABLE audit_logs (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID        REFERENCES users(id) ON DELETE SET NULL,
    actor_id        UUID        REFERENCES users(id) ON DELETE SET NULL,
    application_id  UUID        REFERENCES applications(id) ON DELETE SET NULL,
    session_id      UUID        REFERENCES sessions(id) ON DELETE SET NULL,
    action          audit_action NOT NULL,
    resource_type   TEXT        NOT NULL,
    resource_id     UUID,
    ip_address      INET,
    user_agent      TEXT,
    old_values      JSONB,
    new_values      JSONB,
    metadata        JSONB       NOT NULL DEFAULT '{}',
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
) PARTITION BY RANGE (occurred_at);

CREATE TABLE audit_logs_2026_01 PARTITION OF audit_logs FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_logs_2026_02 PARTITION OF audit_logs FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_logs_2026_03 PARTITION OF audit_logs FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE audit_logs_2026_04 PARTITION OF audit_logs FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE audit_logs_2026_05 PARTITION OF audit_logs FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE audit_logs_default  PARTITION OF audit_logs DEFAULT;

-- Security Events
CREATE TABLE security_events (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID REFERENCES users(id) ON DELETE SET NULL,
    application_id  UUID REFERENCES applications(id) ON DELETE SET NULL,
    event_type      security_event_type     NOT NULL,
    severity        security_event_severity NOT NULL DEFAULT 'medium',
    description     TEXT,
    ip_address      INET,
    user_agent      TEXT,
    country_code    VARCHAR(2),
    risk_score      SMALLINT CHECK (risk_score BETWEEN 0 AND 100),
    resolved        BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_by     UUID REFERENCES users(id),
    resolved_at     TIMESTAMPTZ,
    metadata        JSONB NOT NULL DEFAULT '{}',
    occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- GDPR / Compliance
CREATE TABLE user_consents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    consent_type    consent_type   NOT NULL,
    status          consent_status NOT NULL DEFAULT 'pending',
    version         TEXT NOT NULL,
    given_at        TIMESTAMPTZ,
    withdrawn_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    ip_address      INET,
    user_agent      TEXT,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, tenant_id, consent_type, version)
);

CREATE TABLE data_retention_policies (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource_type   TEXT NOT NULL,
    retention_days  INT  NOT NULL,
    action          retention_policy_type NOT NULL DEFAULT 'delete',
    regulation      regulation_type,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource_type)
);

CREATE TABLE pii_deletion_requests (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    requested_by    UUID REFERENCES users(id),
    status          data_deletion_status NOT NULL DEFAULT 'requested',
    reason          TEXT,
    regulation      regulation_type,
    verified_at     TIMESTAMPTZ,
    scheduled_for   TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    failure_reason  TEXT,
    metadata        JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE data_export_requests (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    requested_by        UUID REFERENCES users(id),
    status              TEXT NOT NULL DEFAULT 'pending'
                            CHECK (status IN ('pending','processing','ready','downloaded','expired','failed')),
    format              TEXT NOT NULL DEFAULT 'json' CHECK (format IN ('json','csv','xml')),
    download_url        TEXT,
    download_token_hash TEXT,
    expires_at          TIMESTAMPTZ,
    completed_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE pii_field_registry (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID REFERENCES tenants(id) ON DELETE CASCADE,
    table_name          TEXT NOT NULL,
    column_name         TEXT NOT NULL,
    classification      data_classification NOT NULL,
    description         TEXT,
    encryption_required BOOLEAN NOT NULL DEFAULT TRUE,
    applicable_regulations regulation_type[] NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name, column_name)
);

-- Password Reset & Magic Links
CREATE TABLE password_reset_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    ip_address  INET,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE magic_links (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID REFERENCES applications(id),
    token_hash      TEXT NOT NULL UNIQUE,
    redirect_url    TEXT,
    used            BOOLEAN NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    ip_address      INET,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE email_verification_tokens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash  TEXT NOT NULL UNIQUE,
    email_hash  TEXT NOT NULL,
    used        BOOLEAN NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    expires_at  TIMESTAMPTZ NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Rate Limiting & IP Management
CREATE TABLE ip_allowlist (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID REFERENCES applications(id) ON DELETE CASCADE,
    cidr            CIDR    NOT NULL,
    description     TEXT,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_by      UUID REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ip_blocklist (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID REFERENCES tenants(id) ON DELETE CASCADE,
    cidr        CIDR NOT NULL,
    reason      TEXT NOT NULL,
    added_by    UUID REFERENCES users(id),
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Webhooks
CREATE TABLE webhooks (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID REFERENCES applications(id) ON DELETE CASCADE,
    url                 TEXT    NOT NULL,
    secret_hash         TEXT,
    events              TEXT[]  NOT NULL DEFAULT '{}',
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    failure_count       INT     NOT NULL DEFAULT 0,
    last_triggered_at   TIMESTAMPTZ,
    last_failure_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE webhook_deliveries (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v7(),
    webhook_id      UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_type      TEXT NOT NULL,
    payload         JSONB NOT NULL DEFAULT '{}',
    response_status INT,
    response_body   TEXT,
    duration_ms     INT,
    success         BOOLEAN NOT NULL DEFAULT FALSE,
    attempt         INT     NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ===========================================================================
-- STEP 5 – updated_at TRIGGERS
-- ===========================================================================
CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_applications_updated_at
    BEFORE UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_mfa_devices_updated_at
    BEFORE UPDATE ON mfa_devices FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_identity_providers_updated_at
    BEFORE UPDATE ON identity_providers FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_oidc_configurations_updated_at
    BEFORE UPDATE ON oidc_configurations FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_saml_configurations_updated_at
    BEFORE UPDATE ON saml_configurations FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_federated_identities_updated_at
    BEFORE UPDATE ON federated_identities FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_user_localization_preferences_updated_at
    BEFORE UPDATE ON user_localization_preferences FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_tenant_regional_settings_updated_at
    BEFORE UPDATE ON tenant_regional_settings FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_ui_translations_updated_at
    BEFORE UPDATE ON ui_translations FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_user_consents_updated_at
    BEFORE UPDATE ON user_consents FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_data_retention_policies_updated_at
    BEFORE UPDATE ON data_retention_policies FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_pii_deletion_requests_updated_at
    BEFORE UPDATE ON pii_deletion_requests FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_data_export_requests_updated_at
    BEFORE UPDATE ON data_export_requests FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();
CREATE TRIGGER trg_webhooks_updated_at
    BEFORE UPDATE ON webhooks FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ===========================================================================
-- STEP 6 – CORE INDEXES
-- ===========================================================================
CREATE INDEX idx_tenants_slug           ON tenants (slug);
CREATE INDEX idx_tenants_status         ON tenants (status) WHERE status <> 'deleted';
CREATE INDEX idx_tenant_domains_domain  ON tenant_domains (domain);
CREATE INDEX idx_users_tenant_status    ON users (tenant_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_users_email_hash       ON users (tenant_id, email_hash);
CREATE INDEX idx_users_created_at       ON users (tenant_id, created_at DESC);
CREATE INDEX idx_applications_client_id ON applications (client_id);
CREATE INDEX idx_sessions_token_hash    ON sessions (session_token_hash);
CREATE INDEX idx_sessions_user_active   ON sessions (user_id, status, expires_at) WHERE status = 'active';
CREATE INDEX idx_sessions_expires_at    ON sessions (expires_at) WHERE status = 'active';
CREATE INDEX idx_mfa_devices_user       ON mfa_devices (user_id, status) WHERE status = 'active';
CREATE INDEX idx_oauth_tokens_hash      ON oauth_tokens (token_hash);
CREATE INDEX idx_oauth_tokens_user      ON oauth_tokens (user_id, status, expires_at) WHERE status = 'active';
CREATE INDEX idx_api_keys_hash          ON api_keys (key_hash);
CREATE INDEX idx_federated_subject      ON federated_identities (tenant_id, provider_id, external_subject);
CREATE INDEX idx_audit_logs_tenant      ON audit_logs (tenant_id, action, occurred_at DESC);
CREATE INDEX idx_audit_logs_user        ON audit_logs (user_id, occurred_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX idx_security_events_open   ON security_events (tenant_id, severity, occurred_at DESC) WHERE resolved = FALSE;
CREATE INDEX idx_pii_deletion_due       ON pii_deletion_requests (status, scheduled_for) WHERE status IN ('requested','in_progress');
CREATE INDEX idx_password_reset_hash    ON password_reset_tokens (token_hash);
CREATE INDEX idx_magic_links_hash       ON magic_links (token_hash);
CREATE INDEX idx_email_verify_hash      ON email_verification_tokens (token_hash);

-- ===========================================================================
-- STEP 7 – RLS HELPER FUNCTIONS
-- ===========================================================================
CREATE OR REPLACE FUNCTION fn_is_super_admin() RETURNS BOOLEAN
    LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT current_setting('app.current_role', TRUE) = 'super_admin'; $$;

CREATE OR REPLACE FUNCTION fn_current_tenant_id() RETURNS UUID
    LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT current_setting('app.current_tenant_id', TRUE)::UUID; $$;

CREATE OR REPLACE FUNCTION fn_current_user_id() RETURNS UUID
    LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT current_setting('app.current_user_id', TRUE)::UUID; $$;

-- ===========================================================================
-- STEP 8 – ROW LEVEL SECURITY
-- ===========================================================================
ALTER TABLE tenants      ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_domains ENABLE ROW LEVEL SECURITY;
ALTER TABLE users        ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_passwords ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_roles   ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications ENABLE ROW LEVEL SECURITY;
ALTER TABLE sessions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices      ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_devices  ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_recovery_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE mfa_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE application_scopes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_authorization_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE oauth_refresh_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_keys     ENABLE ROW LEVEL SECURITY;
ALTER TABLE identity_providers ENABLE ROW LEVEL SECURITY;
ALTER TABLE oidc_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE saml_configurations ENABLE ROW LEVEL SECURITY;
ALTER TABLE federated_identities ENABLE ROW LEVEL SECURITY;
ALTER TABLE sso_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_localization_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_regional_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE ui_translations ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs   ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_consents ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_retention_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE pii_deletion_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE data_export_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks     ENABLE ROW LEVEL SECURITY;

-- Tenant isolation policies (representative set; full set in rls_policies.sql)
CREATE POLICY rls_tenants ON tenants AS RESTRICTIVE
    USING (id = fn_current_tenant_id() OR fn_is_super_admin());
CREATE POLICY rls_users ON users AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());
CREATE POLICY rls_sessions ON sessions AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());
CREATE POLICY rls_audit_logs ON audit_logs AS RESTRICTIVE
    USING (tenant_id = fn_current_tenant_id() OR fn_is_super_admin());

-- ===========================================================================
-- STEP 9 – RECORD MIGRATION
-- ===========================================================================
INSERT INTO schema_migrations (version, description)
VALUES ('001', 'Initial schema: multi-tenant auth framework with UUID v7');

COMMIT;
