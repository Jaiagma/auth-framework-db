-- ============================================================
-- migrations/001_initial_schema.sql
-- Initial migration for the multi-tenant authentication
-- framework.
--
-- This file composes all component SQL files in the correct
-- dependency order and is the single file to apply when
-- bootstrapping a fresh PostgreSQL database.
--
-- Usage:
--   psql -d <database> -f migrations/001_initial_schema.sql
--
-- Or with psql variables to control individual sections:
--   psql -d <database> -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
-- ============================================================

BEGIN;

-- ─── Migration metadata table (created first, once) ──────────
CREATE TABLE IF NOT EXISTS schema_migrations (
    version      TEXT        PRIMARY KEY,
    description  TEXT        NOT NULL,
    applied_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    checksum     TEXT
);

-- Guard: skip if already applied
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM schema_migrations WHERE version = '001') THEN
        RAISE NOTICE 'Migration 001 already applied – skipping.';
    END IF;
END;
$$;

-- ─── Extensions ───────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "unaccent";

-- ─── UUID v7 helper ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION generate_uuid_v7()
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_time       TIMESTAMPTZ := clock_timestamp();
    v_unix_ms    BIGINT;
    v_rand_bytes BYTEA;
    v_uuid_hex   TEXT;
BEGIN
    v_unix_ms    := FLOOR(EXTRACT(EPOCH FROM v_time) * 1000)::BIGINT;
    v_rand_bytes := gen_random_bytes(10);

    v_uuid_hex :=
        LPAD(TO_HEX(v_unix_ms), 12, '0') ||
        '7' ||
        ENCODE(SUBSTRING(v_rand_bytes FROM 1 FOR 2), 'hex') ||
        TO_HEX((get_byte(v_rand_bytes, 2) & x'3f'::INT) | x'80'::INT) ||
        ENCODE(SUBSTRING(v_rand_bytes FROM 4 FOR 7), 'hex');

    RETURN (
        SUBSTRING(v_uuid_hex, 1,  8) || '-' ||
        SUBSTRING(v_uuid_hex, 9,  4) || '-' ||
        SUBSTRING(v_uuid_hex, 13, 4) || '-' ||
        SUBSTRING(v_uuid_hex, 17, 4) || '-' ||
        SUBSTRING(v_uuid_hex, 21, 12)
    )::UUID;
END;
$$;

-- ─── ENUM types ───────────────────────────────────────────────
-- (Inline from enums.sql to make this a self-contained migration)

DO $$ BEGIN CREATE TYPE tenant_status AS ENUM ('active','suspended','pending','deleted'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE application_type AS ENUM ('web','mobile','spa','native','service','browser_ext'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE user_status AS ENUM ('active','inactive','locked','pending_verification','suspended','deleted'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE credential_type AS ENUM ('password','passkey','magic_link','certificate'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE user_role_type AS ENUM ('super_admin','tenant_admin','app_admin','user','guest','service_account','read_only'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE mfa_method_type AS ENUM ('totp','sms','email','webauthn','push','backup_code'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE mfa_device_status AS ENUM ('active','inactive','revoked','pending_activation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE session_status AS ENUM ('active','expired','revoked','logged_out'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE oauth_grant_type AS ENUM ('authorization_code','client_credentials','refresh_token','device_code','implicit','password'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE oauth_token_type AS ENUM ('access_token','refresh_token','id_token'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE oauth_token_status AS ENUM ('active','expired','revoked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE oauth_response_type AS ENUM ('code','token','id_token','code token','code id_token','token id_token','code token id_token'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE oauth_scope_type AS ENUM ('openid','profile','email','phone','address','offline_access','read','write','admin','api','mfa','impersonation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE idp_type AS ENUM ('saml2','oidc','oauth2','ldap','active_directory','google','github','microsoft','apple','facebook','twitter','linkedin','auth0','okta','onelogin','pingidentity','custom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE idp_status AS ENUM ('active','inactive','testing','deprecated'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE federated_identity_status AS ENUM ('active','unlinked','suspended'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE sso_protocol AS ENUM ('saml2','oidc','wsfed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE sso_session_status AS ENUM ('active','expired','logged_out'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE audit_event_type AS ENUM ('login_success','login_failure','logout','session_expired','session_revoked','mfa_enrolled','mfa_verified','mfa_failed','mfa_revoked','recovery_code_used','user_created','user_updated','user_deleted','user_suspended','user_activated','password_changed','password_reset_requested','email_verified','token_issued','token_refreshed','token_revoked','authorization_granted','authorization_denied','sso_login','sso_logout','idp_linked','idp_unlinked','tenant_created','tenant_updated','role_assigned','role_revoked','permission_granted','permission_revoked','consent_given','consent_withdrawn','data_export_requested','data_deletion_requested','data_deleted','suspicious_activity','rate_limit_exceeded','ip_blocked','brute_force_detected','api_key_created','api_key_revoked'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE audit_severity AS ENUM ('info','warning','error','critical'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE consent_type AS ENUM ('terms_of_service','privacy_policy','cookie_policy','marketing_emails','analytics','data_processing','data_sharing','third_party_integrations','biometric_data','geolocation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE consent_status AS ENUM ('granted','withdrawn','expired','pending'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE deletion_request_status AS ENUM ('pending','in_progress','completed','failed','cancelled'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE pii_classification AS ENUM ('public','internal','confidential','restricted','sensitive_pii','financial','health'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE pii_regulation AS ENUM ('gdpr','ccpa','hipaa','coppa','pipeda','lgpd','pdpa','eidas','ferpa','glba'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE risk_level AS ENUM ('low','medium','high','critical'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE security_event_type AS ENUM ('brute_force','credential_stuffing','account_takeover','bot_activity','impossible_travel','new_device','new_location','leaked_credential','suspicious_ip','anomalous_behavior','privilege_escalation'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE security_event_status AS ENUM ('open','investigating','mitigated','resolved','false_positive'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE device_trust_level AS ENUM ('unknown','unverified','verified','managed'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE data_residency_region AS ENUM ('us','eu','uk','ca','au','ap','global'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE regulation_region AS ENUM ('eu','us','us_california','us_virginia','uk','canada','brazil','australia','india','singapore','japan','global'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─── Schema tables ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS tenants (
    id                   UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    name                 TEXT        NOT NULL,
    slug                 TEXT        NOT NULL UNIQUE,
    display_name         TEXT,
    logo_url             TEXT,
    status               tenant_status NOT NULL DEFAULT 'active',
    plan                 TEXT        NOT NULL DEFAULT 'free',
    data_residency       data_residency_region NOT NULL DEFAULT 'global',
    max_users            INT,
    max_applications     INT,
    allowed_mfa_methods  mfa_method_type[]  NOT NULL DEFAULT ARRAY['totp','email']::mfa_method_type[],
    require_mfa          BOOLEAN     NOT NULL DEFAULT FALSE,
    session_lifetime_sec INT         NOT NULL DEFAULT 86400,
    metadata             JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMPTZ,
    CONSTRAINT tenants_slug_fmt CHECK (slug ~ '^[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]$')
);

CREATE TABLE IF NOT EXISTS tenant_settings (
    id                          UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id                   UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    password_min_length         INT   NOT NULL DEFAULT 8,
    password_require_uppercase  BOOLEAN NOT NULL DEFAULT TRUE,
    password_require_numbers    BOOLEAN NOT NULL DEFAULT TRUE,
    password_require_symbols    BOOLEAN NOT NULL DEFAULT FALSE,
    password_history_count      INT   NOT NULL DEFAULT 5,
    max_login_attempts          INT   NOT NULL DEFAULT 5,
    lockout_duration_sec        INT   NOT NULL DEFAULT 900,
    session_idle_timeout_sec    INT   NOT NULL DEFAULT 3600,
    concurrent_sessions_max     INT   NOT NULL DEFAULT 5,
    refresh_token_lifetime_sec  INT   NOT NULL DEFAULT 2592000,
    support_email               TEXT,
    from_email                  TEXT,
    custom_domain               TEXT,
    gdpr_enabled                BOOLEAN NOT NULL DEFAULT FALSE,
    ccpa_enabled                BOOLEAN NOT NULL DEFAULT FALSE,
    data_retention_days         INT   NOT NULL DEFAULT 365,
    default_language            TEXT  NOT NULL DEFAULT 'en',
    default_timezone            TEXT  NOT NULL DEFAULT 'UTC',
    allowed_countries           TEXT[],
    sso_enabled                 BOOLEAN NOT NULL DEFAULT FALSE,
    mfa_enabled                 BOOLEAN NOT NULL DEFAULT TRUE,
    oauth_enabled               BOOLEAN NOT NULL DEFAULT TRUE,
    registration_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    magic_link_enabled          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id)
);

CREATE TABLE IF NOT EXISTS organizations (
    id            UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id     UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    parent_id     UUID        REFERENCES organizations(id) ON DELETE SET NULL,
    name          TEXT        NOT NULL,
    slug          TEXT        NOT NULL,
    description   TEXT,
    metadata      JSONB,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ,
    UNIQUE (tenant_id, slug)
);

CREATE TABLE IF NOT EXISTS applications (
    id                  UUID             PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id           UUID             NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                TEXT             NOT NULL,
    slug                TEXT             NOT NULL,
    description         TEXT,
    app_type            application_type NOT NULL DEFAULT 'web',
    logo_url            TEXT,
    homepage_url        TEXT,
    privacy_policy_url  TEXT,
    tos_url             TEXT,
    client_id           TEXT             NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
    client_secret_hash  TEXT,
    redirect_uris       TEXT[]           NOT NULL DEFAULT '{}',
    post_logout_uris    TEXT[]           NOT NULL DEFAULT '{}',
    allowed_origins     TEXT[]           NOT NULL DEFAULT '{}',
    access_token_ttl    INT              NOT NULL DEFAULT 3600,
    refresh_token_ttl   INT              NOT NULL DEFAULT 2592000,
    id_token_ttl        INT              NOT NULL DEFAULT 3600,
    is_active           BOOLEAN          NOT NULL DEFAULT TRUE,
    is_first_party      BOOLEAN          NOT NULL DEFAULT FALSE,
    require_pkce        BOOLEAN          NOT NULL DEFAULT TRUE,
    metadata            JSONB,
    created_at          TIMESTAMPTZ      NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ      NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE (tenant_id, slug)
);

CREATE TABLE IF NOT EXISTS roles (
    id          UUID          PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT          NOT NULL,
    description TEXT,
    is_system   BOOLEAN       NOT NULL DEFAULT FALSE,
    metadata    JSONB,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE IF NOT EXISTS permissions (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource    TEXT        NOT NULL,
    action      TEXT        NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource, action)
);

CREATE TABLE IF NOT EXISTS role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by    UUID,
    PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE IF NOT EXISTS users (
    id                    UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id             UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id        UUID        REFERENCES applications(id) ON DELETE SET NULL,
    organization_id       UUID        REFERENCES organizations(id) ON DELETE SET NULL,
    email_encrypted       BYTEA       NOT NULL,
    email_hash            TEXT        NOT NULL,
    phone_encrypted       BYTEA,
    phone_hash            TEXT,
    username              TEXT,
    status                user_status NOT NULL DEFAULT 'pending_verification',
    email_verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    email_verified_at     TIMESTAMPTZ,
    phone_verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    phone_verified_at     TIMESTAMPTZ,
    mfa_enabled           BOOLEAN     NOT NULL DEFAULT FALSE,
    mfa_enforced_at       TIMESTAMPTZ,
    last_password_changed_at TIMESTAMPTZ,
    last_login_at         TIMESTAMPTZ,
    last_login_ip         INET,
    failed_login_count    INT         NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,
    gdpr_consent_at       TIMESTAMPTZ,
    data_deletion_requested_at TIMESTAMPTZ,
    metadata              JSONB,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at            TIMESTAMPTZ,
    UNIQUE (tenant_id, email_hash),
    UNIQUE (tenant_id, username)
);

CREATE TABLE IF NOT EXISTS user_profiles (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    first_name_encrypted  BYTEA,
    last_name_encrypted   BYTEA,
    display_name          TEXT,
    avatar_url            TEXT,
    birth_year        SMALLINT,
    gender            TEXT,
    locale            TEXT    DEFAULT 'en',
    timezone          TEXT    DEFAULT 'UTC',
    address_encrypted BYTEA,
    country_code      CHAR(2),
    preferences       JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS user_credentials (
    id                  UUID            PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    credential_type     credential_type NOT NULL DEFAULT 'password',
    password_hash       TEXT,
    password_history    TEXT[]          NOT NULL DEFAULT '{}',
    public_key          BYTEA,
    credential_id       TEXT,
    token_hash          TEXT,
    token_expires_at    TIMESTAMPTZ,
    is_primary          BOOLEAN         NOT NULL DEFAULT TRUE,
    last_used_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_roles (
    id              UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id         UUID        NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID        REFERENCES applications(id) ON DELETE SET NULL,
    expires_at      TIMESTAMPTZ,
    assigned_by     UUID,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, role_id, application_id)
);

CREATE TABLE IF NOT EXISTS device_fingerprints (
    id                 UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id            UUID              REFERENCES users(id) ON DELETE CASCADE,
    tenant_id          UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    fingerprint_hash   TEXT              NOT NULL,
    device_type        TEXT,
    os                 TEXT,
    os_version         TEXT,
    browser            TEXT,
    browser_version    TEXT,
    screen_resolution  TEXT,
    trust_level        device_trust_level NOT NULL DEFAULT 'unknown',
    trusted_at         TIMESTAMPTZ,
    country_code       CHAR(2),
    city               TEXT,
    first_seen_at      TIMESTAMPTZ        NOT NULL DEFAULT now(),
    last_seen_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    seen_count         INT                NOT NULL DEFAULT 1,
    UNIQUE (tenant_id, fingerprint_hash)
);

CREATE TABLE IF NOT EXISTS user_sessions (
    id               UUID           PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID           NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id   UUID           REFERENCES applications(id) ON DELETE SET NULL,
    status           session_status NOT NULL DEFAULT 'active',
    token_hash       TEXT           NOT NULL UNIQUE,
    refresh_token_hash TEXT,
    ip_address       INET,
    user_agent       TEXT,
    device_fingerprint_id UUID      REFERENCES device_fingerprints(id) ON DELETE SET NULL,
    sso_session_id   UUID,
    idp_session_id   TEXT,
    last_active_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ    NOT NULL,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    revoked_at       TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS mfa_devices (
    id             UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id        UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id      UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    method         mfa_method_type   NOT NULL,
    name           TEXT,
    status         mfa_device_status NOT NULL DEFAULT 'pending_activation',
    totp_secret_encrypted  BYTEA,
    totp_issuer    TEXT,
    totp_algorithm TEXT    DEFAULT 'SHA1',
    totp_digits    SMALLINT DEFAULT 6,
    totp_period    SMALLINT DEFAULT 30,
    destination_encrypted BYTEA,
    credential_id        TEXT,
    public_key_cbor      BYTEA,
    aaguid               TEXT,
    sign_count           BIGINT      DEFAULT 0,
    rp_id                TEXT,
    push_token_encrypted BYTEA,
    push_provider        TEXT,
    last_used_at         TIMESTAMPTZ,
    verified_at          TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfa_recovery_codes (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    code_hash   TEXT        NOT NULL,
    used        BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS mfa_challenges (
    id            UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id       UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id     UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id     UUID              REFERENCES mfa_devices(id) ON DELETE CASCADE,
    method        mfa_method_type   NOT NULL,
    challenge     TEXT              NOT NULL,
    is_verified   BOOLEAN           NOT NULL DEFAULT FALSE,
    expires_at    TIMESTAMPTZ       NOT NULL,
    verified_at   TIMESTAMPTZ,
    ip_address    INET,
    created_at    TIMESTAMPTZ       NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS oauth_scopes (
    id          UUID            PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT            NOT NULL,
    description TEXT,
    is_default  BOOLEAN         NOT NULL DEFAULT FALSE,
    is_public   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE IF NOT EXISTS oauth_authorization_codes (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id    UUID        NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash         TEXT        NOT NULL UNIQUE,
    redirect_uri      TEXT        NOT NULL,
    scopes            TEXT[]      NOT NULL DEFAULT '{}',
    code_challenge        TEXT,
    code_challenge_method TEXT    CHECK (code_challenge_method IN ('S256', 'plain')),
    nonce             TEXT,
    state             TEXT,
    is_used           BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at        TIMESTAMPTZ NOT NULL,
    used_at           TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS oauth_tokens (
    id                UUID             PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID             NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id    UUID             NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id           UUID             REFERENCES users(id) ON DELETE CASCADE,
    token_type        oauth_token_type NOT NULL,
    token_hash        TEXT             NOT NULL UNIQUE,
    status            oauth_token_status NOT NULL DEFAULT 'active',
    scopes            TEXT[]           NOT NULL DEFAULT '{}',
    parent_token_id   UUID             REFERENCES oauth_tokens(id) ON DELETE SET NULL,
    claims            JSONB,
    session_id        UUID             REFERENCES user_sessions(id) ON DELETE SET NULL,
    issued_at         TIMESTAMPTZ      NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ      NOT NULL,
    last_used_at      TIMESTAMPTZ,
    revoked_at        TIMESTAMPTZ,
    revocation_reason TEXT,
    client_ip         INET,
    created_at        TIMESTAMPTZ      NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS oauth_application_scopes (
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    scope_id       UUID NOT NULL REFERENCES oauth_scopes(id) ON DELETE CASCADE,
    PRIMARY KEY (application_id, scope_id)
);

CREATE TABLE IF NOT EXISTS identity_providers (
    id               UUID       PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID       NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name             TEXT       NOT NULL,
    slug             TEXT       NOT NULL,
    provider_type    idp_type   NOT NULL,
    status           idp_status NOT NULL DEFAULT 'active',
    issuer_url       TEXT,
    authorization_endpoint TEXT,
    token_endpoint   TEXT,
    userinfo_endpoint TEXT,
    jwks_uri         TEXT,
    client_id        TEXT,
    client_secret_encrypted BYTEA,
    entity_id        TEXT,
    metadata_url     TEXT,
    sso_url          TEXT,
    slo_url          TEXT,
    x509_cert        TEXT,
    auto_provision   BOOLEAN    NOT NULL DEFAULT FALSE,
    sync_on_login    BOOLEAN    NOT NULL DEFAULT TRUE,
    default_role_id  UUID       REFERENCES roles(id) ON DELETE SET NULL,
    attribute_mapping JSONB,
    logo_url         TEXT,
    button_label     TEXT,
    config           JSONB,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, slug)
);

CREATE TABLE IF NOT EXISTS saml_configurations (
    id                   UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id            UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id               UUID  NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    sp_entity_id         TEXT  NOT NULL,
    sp_acs_url           TEXT  NOT NULL,
    sp_slo_url           TEXT,
    sp_metadata_url      TEXT,
    sp_private_key_encrypted BYTEA,
    sp_certificate       TEXT,
    sign_requests        BOOLEAN NOT NULL DEFAULT TRUE,
    sign_assertions      BOOLEAN NOT NULL DEFAULT TRUE,
    encrypt_assertions   BOOLEAN NOT NULL DEFAULT FALSE,
    signature_algorithm  TEXT    NOT NULL DEFAULT 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
    digest_algorithm     TEXT    NOT NULL DEFAULT 'http://www.w3.org/2001/04/xmlenc#sha256',
    name_id_format       TEXT    NOT NULL DEFAULT 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
    attribute_mapping    JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id)
);

CREATE TABLE IF NOT EXISTS oidc_configurations (
    id                   UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id            UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id               UUID  NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    discovery_url        TEXT,
    client_id            TEXT  NOT NULL,
    client_secret_encrypted BYTEA,
    response_type        TEXT  NOT NULL DEFAULT 'code',
    scopes               TEXT[] NOT NULL DEFAULT ARRAY['openid','profile','email'],
    id_token_signing_alg TEXT  NOT NULL DEFAULT 'RS256',
    use_pkce             BOOLEAN NOT NULL DEFAULT TRUE,
    pkce_method          TEXT    NOT NULL DEFAULT 'S256',
    claims_mapping       JSONB,
    extra_params         JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id)
);

CREATE TABLE IF NOT EXISTS sso_sessions (
    id                 UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id          UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id            UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idp_id             UUID              REFERENCES identity_providers(id) ON DELETE SET NULL,
    protocol           sso_protocol      NOT NULL,
    status             sso_session_status NOT NULL DEFAULT 'active',
    idp_session_id     TEXT,
    idp_name_id        TEXT,
    participating_apps UUID[]            NOT NULL DEFAULT '{}',
    id_token           TEXT,
    saml_assertion_id  TEXT,
    authenticated_at   TIMESTAMPTZ       NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ       NOT NULL,
    last_active_at     TIMESTAMPTZ       NOT NULL DEFAULT now(),
    logged_out_at      TIMESTAMPTZ,
    ip_address         INET,
    user_agent         TEXT,
    created_at         TIMESTAMPTZ       NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS federated_identities (
    id                  UUID                    PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id             UUID                    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id              UUID                    NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    status              federated_identity_status NOT NULL DEFAULT 'active',
    subject             TEXT                    NOT NULL,
    access_token_encrypted  BYTEA,
    refresh_token_encrypted BYTEA,
    token_expires_at    TIMESTAMPTZ,
    idp_profile         JSONB,
    email               TEXT,
    name                TEXT,
    picture_url         TEXT,
    last_login_at       TIMESTAMPTZ,
    linked_at           TIMESTAMPTZ             NOT NULL DEFAULT now(),
    unlinked_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id, subject)
);

CREATE TABLE IF NOT EXISTS linked_accounts (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    target_user_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    link_type        TEXT        NOT NULL DEFAULT 'same_person',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, target_user_id)
);

CREATE TABLE IF NOT EXISTS languages (
    id           UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    code         CHAR(5) NOT NULL UNIQUE,
    name         TEXT  NOT NULL,
    native_name  TEXT  NOT NULL,
    is_rtl       BOOLEAN NOT NULL DEFAULT FALSE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order   SMALLINT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS timezones (
    id           UUID     PRIMARY KEY DEFAULT generate_uuid_v7(),
    name         TEXT     NOT NULL UNIQUE,
    abbreviation TEXT,
    utc_offset   INTERVAL NOT NULL,
    has_dst      BOOLEAN  NOT NULL DEFAULT FALSE,
    region       TEXT,
    is_active    BOOLEAN  NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_localization_preferences (
    id               UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    language_code    TEXT  NOT NULL DEFAULT 'en',
    timezone         TEXT  NOT NULL DEFAULT 'UTC',
    date_format      TEXT  NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format      TEXT  NOT NULL DEFAULT 'HH:mm',
    number_format    TEXT  NOT NULL DEFAULT '1,234.56',
    currency         CHAR(3) NOT NULL DEFAULT 'USD',
    first_day_of_week SMALLINT NOT NULL DEFAULT 1,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS tenant_regional_settings (
    id                       UUID               PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id                UUID               NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    regulation               regulation_region  NOT NULL,
    data_residency           data_residency_region NOT NULL,
    gdpr_enabled             BOOLEAN            NOT NULL DEFAULT FALSE,
    ccpa_enabled             BOOLEAN            NOT NULL DEFAULT FALSE,
    eidas_enabled            BOOLEAN            NOT NULL DEFAULT FALSE,
    restrict_cross_border    BOOLEAN            NOT NULL DEFAULT FALSE,
    allowed_transfer_regions data_residency_region[],
    data_retention_days      INT                NOT NULL DEFAULT 365,
    consent_required         BOOLEAN            NOT NULL DEFAULT TRUE,
    created_at               TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ        NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, regulation)
);

CREATE TABLE IF NOT EXISTS ui_translations (
    id           UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id    UUID  REFERENCES tenants(id) ON DELETE CASCADE,
    language_code TEXT NOT NULL,
    namespace    TEXT NOT NULL DEFAULT 'common',
    key          TEXT NOT NULL,
    value        TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, language_code, namespace, key)
);

CREATE TABLE IF NOT EXISTS audit_logs (
    id               UUID             PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID             NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_type       audit_event_type NOT NULL,
    severity         audit_severity   NOT NULL DEFAULT 'info',
    actor_user_id    UUID             REFERENCES users(id) ON DELETE SET NULL,
    actor_type       TEXT             NOT NULL DEFAULT 'user',
    resource_type    TEXT,
    resource_id      TEXT,
    application_id   UUID             REFERENCES applications(id) ON DELETE SET NULL,
    session_id       UUID,
    ip_address       INET,
    user_agent       TEXT,
    country_code     CHAR(2),
    region_code      TEXT,
    outcome          TEXT             NOT NULL DEFAULT 'success',
    error_code       TEXT,
    error_message    TEXT,
    metadata         JSONB,
    previous_log_id  UUID             REFERENCES audit_logs(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ      NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_consents (
    id               UUID           PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID           NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    consent_type     consent_type   NOT NULL,
    status           consent_status NOT NULL DEFAULT 'pending',
    document_version TEXT           NOT NULL DEFAULT '1.0',
    document_url     TEXT,
    ip_address       INET,
    user_agent       TEXT,
    method           TEXT           NOT NULL DEFAULT 'explicit',
    granted_at       TIMESTAMPTZ,
    withdrawn_at     TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_consent_type UNIQUE (user_id, consent_type)
);

CREATE TABLE IF NOT EXISTS data_retention_policies (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    table_name        TEXT        NOT NULL,
    retention_days    INT         NOT NULL,
    filter_column     TEXT        NOT NULL DEFAULT 'deleted_at',
    is_hard_delete    BOOLEAN     NOT NULL DEFAULT FALSE,
    regulation        pii_regulation,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    last_run_at       TIMESTAMPTZ,
    next_run_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name)
);

CREATE TABLE IF NOT EXISTS pii_deletion_requests (
    id              UUID                    PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id       UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID                    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          deletion_request_status NOT NULL DEFAULT 'pending',
    request_type    TEXT                    NOT NULL DEFAULT 'erasure',
    regulation      pii_regulation,
    requested_at    TIMESTAMPTZ             NOT NULL DEFAULT now(),
    deadline_at     TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    failed_at       TIMESTAMPTZ,
    failure_reason  TEXT,
    requested_by    UUID                    REFERENCES users(id) ON DELETE SET NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS security_events (
    id               UUID                  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID                  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id          UUID                  REFERENCES users(id) ON DELETE SET NULL,
    event_type       security_event_type   NOT NULL,
    risk_level       risk_level            NOT NULL DEFAULT 'low',
    status           security_event_status NOT NULL DEFAULT 'open',
    ip_address       INET,
    user_agent       TEXT,
    country_code     CHAR(2),
    description      TEXT,
    metadata         JSONB,
    resolved_by      UUID                  REFERENCES users(id) ON DELETE SET NULL,
    resolved_at      TIMESTAMPTZ,
    resolution_note  TEXT,
    created_at       TIMESTAMPTZ           NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ           NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS rate_limit_configs (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource         TEXT        NOT NULL,
    max_requests     INT         NOT NULL,
    window_sec       INT         NOT NULL,
    scope            TEXT        NOT NULL DEFAULT 'ip',
    action           TEXT        NOT NULL DEFAULT 'block',
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource, scope)
);

CREATE TABLE IF NOT EXISTS ip_allowlists (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    cidr        CIDR        NOT NULL,
    description TEXT,
    is_blocklist BOOLEAN    NOT NULL DEFAULT FALSE,
    expires_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_by  UUID        REFERENCES users(id) ON DELETE SET NULL,
    UNIQUE (tenant_id, cidr, is_blocklist)
);

CREATE TABLE IF NOT EXISTS pii_data_classifications (
    id               UUID               PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID               REFERENCES tenants(id) ON DELETE CASCADE,
    table_name       TEXT               NOT NULL,
    column_name      TEXT               NOT NULL,
    classification   pii_classification NOT NULL DEFAULT 'internal',
    regulations      pii_regulation[]   NOT NULL DEFAULT '{}',
    is_encrypted     BOOLEAN            NOT NULL DEFAULT FALSE,
    encryption_key_id TEXT,
    notes            TEXT,
    created_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name, column_name)
);

CREATE TABLE IF NOT EXISTS api_keys (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id   UUID        REFERENCES applications(id) ON DELETE SET NULL,
    user_id          UUID        REFERENCES users(id) ON DELETE SET NULL,
    name             TEXT        NOT NULL,
    key_hash         TEXT        NOT NULL UNIQUE,
    key_prefix       CHAR(8)     NOT NULL,
    scopes           TEXT[]      NOT NULL DEFAULT '{}',
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    expires_at       TIMESTAMPTZ,
    last_used_at     TIMESTAMPTZ,
    last_used_ip     INET,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at       TIMESTAMPTZ,
    revoked_by       UUID        REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    is_used     BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    ip_address  INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS email_verification_tokens (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    email_hash  TEXT        NOT NULL,
    is_used     BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at  TIMESTAMPTZ NOT NULL,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─── Functions ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION sha256_hex(value TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT encode(digest(value, 'sha256'), 'hex');
$$;

CREATE OR REPLACE FUNCTION encrypt_pii(plaintext TEXT, aes_key TEXT)
RETURNS BYTEA LANGUAGE plpgsql AS $$
BEGIN
    IF plaintext IS NULL THEN RETURN NULL; END IF;
    RETURN pgp_sym_encrypt(plaintext, aes_key, 'cipher-algo=aes256');
END;
$$;

CREATE OR REPLACE FUNCTION decrypt_pii(ciphertext BYTEA, aes_key TEXT)
RETURNS TEXT LANGUAGE plpgsql AS $$
BEGIN
    IF ciphertext IS NULL THEN RETURN NULL; END IF;
    RETURN pgp_sym_decrypt(ciphertext, aes_key);
EXCEPTION WHEN others THEN RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END;
$$;

CREATE OR REPLACE FUNCTION log_audit_event(
    p_tenant_id      UUID,
    p_event_type     audit_event_type,
    p_actor_user_id  UUID    DEFAULT NULL,
    p_actor_type     TEXT    DEFAULT 'user',
    p_resource_type  TEXT    DEFAULT NULL,
    p_resource_id    TEXT    DEFAULT NULL,
    p_outcome        TEXT    DEFAULT 'success',
    p_ip_address     INET    DEFAULT NULL,
    p_application_id UUID    DEFAULT NULL,
    p_session_id     UUID    DEFAULT NULL,
    p_metadata       JSONB   DEFAULT NULL,
    p_severity       audit_severity DEFAULT 'info'
)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE v_id UUID; v_prev UUID;
BEGIN
    SELECT id INTO v_prev FROM audit_logs WHERE tenant_id = p_tenant_id ORDER BY created_at DESC LIMIT 1;
    INSERT INTO audit_logs (tenant_id, event_type, severity, actor_user_id, actor_type, resource_type, resource_id, application_id, session_id, ip_address, outcome, metadata, previous_log_id)
    VALUES (p_tenant_id, p_event_type, p_severity, p_actor_user_id, p_actor_type, p_resource_type, p_resource_id, p_application_id, p_session_id, p_ip_address, p_outcome, p_metadata, v_prev)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$;

-- ─── Triggers ─────────────────────────────────────────────────

-- updated_at triggers
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at := now(); RETURN NEW; END; $$;

DO $$ DECLARE t TEXT; BEGIN
    FOR t IN SELECT unnest(ARRAY[
        'tenants','tenant_settings','organizations','applications','roles','users',
        'user_profiles','user_credentials','mfa_devices','identity_providers',
        'saml_configurations','oidc_configurations','user_localization_preferences',
        'tenant_regional_settings','ui_translations','user_consents',
        'data_retention_policies','pii_deletion_requests','security_events',
        'rate_limit_configs','pii_data_classifications','api_keys','federated_identities'
    ])
    LOOP
        EXECUTE format(
            'DROP TRIGGER IF EXISTS trg_%s_updated_at ON %I;
             CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at();',
            t, t, t, t
        );
    END LOOP;
END; $$;

-- Deletion deadline trigger
CREATE OR REPLACE FUNCTION set_deletion_deadline() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF NEW.deadline_at IS NULL THEN NEW.deadline_at := NEW.requested_at + INTERVAL '30 days'; END IF; RETURN NEW; END;
$$;
DROP TRIGGER IF EXISTS trg_set_deletion_deadline ON pii_deletion_requests;
CREATE TRIGGER trg_set_deletion_deadline BEFORE INSERT ON pii_deletion_requests FOR EACH ROW EXECUTE FUNCTION set_deletion_deadline();

-- ─── Indexes ──────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_tenants_slug           ON tenants (slug);
CREATE INDEX IF NOT EXISTS idx_tenants_status         ON tenants (status) WHERE status <> 'deleted';
CREATE INDEX IF NOT EXISTS idx_users_tenant           ON users (tenant_id);
CREATE INDEX IF NOT EXISTS idx_users_email_hash       ON users (tenant_id, email_hash);
CREATE INDEX IF NOT EXISTS idx_users_status           ON users (tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_sessions_user          ON user_sessions (user_id, status);
CREATE INDEX IF NOT EXISTS idx_sessions_expires       ON user_sessions (expires_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_tokens_user            ON oauth_tokens (user_id, token_type, status);
CREATE INDEX IF NOT EXISTS idx_tokens_expires         ON oauth_tokens (expires_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_audit_tenant           ON audit_logs (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_actor            ON audit_logs (actor_user_id, created_at DESC) WHERE actor_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_mfa_devices_active     ON mfa_devices (user_id, status) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_pii_del_req_deadline   ON pii_deletion_requests (deadline_at) WHERE status IN ('pending','in_progress');
CREATE INDEX IF NOT EXISTS idx_audit_created_brin     ON audit_logs USING BRIN (created_at);

-- ─── Record migration ─────────────────────────────────────────

INSERT INTO schema_migrations (version, description)
VALUES ('001', 'Initial schema – multi-tenant auth framework')
ON CONFLICT (version) DO NOTHING;

COMMIT;
