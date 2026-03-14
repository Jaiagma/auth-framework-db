-- ============================================================
-- schema.sql
-- Complete PostgreSQL database schema for the multi-tenant
-- authentication framework.
--
-- Prerequisites: enums.sql must be executed first.
-- ============================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- trigram full-text search
CREATE EXTENSION IF NOT EXISTS "btree_gin";  -- GIN indexes on scalar cols
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- locale-insensitive search

-- ────────────────────────────────────────────────────────────
-- UUID v7 helper
-- Generates a sortable, timestamp-prefixed UUID (RFC draft).
-- ────────────────────────────────────────────────────────────
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

    -- Build 128-bit value:
    --   bits  0-47  : unix_ts_ms (48 bits)
    --   bits 48-51  : version 7
    --   bits 52-63  : random_a  (12 bits)
    --   bits 64-65  : variant 10
    --   bits 66-127 : random_b  (62 bits)
    v_uuid_hex :=
        LPAD(TO_HEX(v_unix_ms), 12, '0') ||
        '7' ||
        ENCODE(SUBSTRING(v_rand_bytes FROM 1 FOR 2), 'hex') ||
        -- set variant bits (10xx xxxx) on byte index 8
        TO_HEX((get_byte(v_rand_bytes, 2) & x'3f'::INT) | x'80'::INT) ||
        ENCODE(SUBSTRING(v_rand_bytes FROM 4 FOR 7), 'hex');

    -- Format as 8-4-4-4-12
    RETURN (
        SUBSTRING(v_uuid_hex, 1,  8) || '-' ||
        SUBSTRING(v_uuid_hex, 9,  4) || '-' ||
        SUBSTRING(v_uuid_hex, 13, 4) || '-' ||
        SUBSTRING(v_uuid_hex, 17, 4) || '-' ||
        SUBSTRING(v_uuid_hex, 21, 12)
    )::UUID;
END;
$$;

-- ============================================================
-- SECTION 1 – TENANTS & ORGANIZATIONS
-- ============================================================

CREATE TABLE tenants (
    id                   UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    name                 TEXT        NOT NULL,
    slug                 TEXT        NOT NULL UNIQUE,  -- URL-safe identifier
    display_name         TEXT,
    logo_url             TEXT,
    status               tenant_status NOT NULL DEFAULT 'active',
    plan                 TEXT        NOT NULL DEFAULT 'free',  -- pricing tier
    data_residency       data_residency_region NOT NULL DEFAULT 'global',
    max_users            INT,
    max_applications     INT,
    allowed_mfa_methods  mfa_method_type[]  NOT NULL DEFAULT ARRAY['totp','email']::mfa_method_type[],
    require_mfa          BOOLEAN     NOT NULL DEFAULT FALSE,
    session_lifetime_sec INT         NOT NULL DEFAULT 86400,  -- 24 h
    metadata             JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMPTZ,
    CONSTRAINT tenants_slug_fmt CHECK (slug ~ '^[a-z0-9][a-z0-9\-]{1,61}[a-z0-9]$')
);

CREATE TABLE tenant_settings (
    id                          UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id                   UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- Security
    password_min_length         INT   NOT NULL DEFAULT 8,
    password_require_uppercase  BOOLEAN NOT NULL DEFAULT TRUE,
    password_require_numbers    BOOLEAN NOT NULL DEFAULT TRUE,
    password_require_symbols    BOOLEAN NOT NULL DEFAULT FALSE,
    password_history_count      INT   NOT NULL DEFAULT 5,
    max_login_attempts          INT   NOT NULL DEFAULT 5,
    lockout_duration_sec        INT   NOT NULL DEFAULT 900,   -- 15 min
    -- Session
    session_idle_timeout_sec    INT   NOT NULL DEFAULT 3600,  -- 1 h
    concurrent_sessions_max     INT   NOT NULL DEFAULT 5,
    refresh_token_lifetime_sec  INT   NOT NULL DEFAULT 2592000, -- 30 d
    -- Email / Branding
    support_email               TEXT,
    from_email                  TEXT,
    custom_domain               TEXT,
    -- Compliance
    gdpr_enabled                BOOLEAN NOT NULL DEFAULT FALSE,
    ccpa_enabled                BOOLEAN NOT NULL DEFAULT FALSE,
    data_retention_days         INT   NOT NULL DEFAULT 365,
    -- Localization
    default_language            TEXT  NOT NULL DEFAULT 'en',
    default_timezone            TEXT  NOT NULL DEFAULT 'UTC',
    allowed_countries           TEXT[],   -- ISO-3166 alpha-2 whitelist
    -- Feature flags
    sso_enabled                 BOOLEAN NOT NULL DEFAULT FALSE,
    mfa_enabled                 BOOLEAN NOT NULL DEFAULT TRUE,
    oauth_enabled               BOOLEAN NOT NULL DEFAULT TRUE,
    registration_enabled        BOOLEAN NOT NULL DEFAULT TRUE,
    magic_link_enabled          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id)
);

CREATE TABLE organizations (
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

CREATE TABLE applications (
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
    -- OAuth client credentials
    client_id           TEXT             NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
    client_secret_hash  TEXT,            -- bcrypt hash; NULL = public client
    -- Allowed callbacks / origins
    redirect_uris       TEXT[]           NOT NULL DEFAULT '{}',
    post_logout_uris    TEXT[]           NOT NULL DEFAULT '{}',
    allowed_origins     TEXT[]           NOT NULL DEFAULT '{}',
    -- Token settings
    access_token_ttl    INT              NOT NULL DEFAULT 3600,
    refresh_token_ttl   INT              NOT NULL DEFAULT 2592000,
    id_token_ttl        INT              NOT NULL DEFAULT 3600,
    -- Flags
    is_active           BOOLEAN          NOT NULL DEFAULT TRUE,
    is_first_party      BOOLEAN          NOT NULL DEFAULT FALSE,
    require_pkce        BOOLEAN          NOT NULL DEFAULT TRUE,
    metadata            JSONB,
    created_at          TIMESTAMPTZ      NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ      NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,
    UNIQUE (tenant_id, slug)
);

-- ============================================================
-- SECTION 2 – ROLES & PERMISSIONS
-- ============================================================

CREATE TABLE roles (
    id          UUID          PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT          NOT NULL,
    description TEXT,
    is_system   BOOLEAN       NOT NULL DEFAULT FALSE, -- system roles cannot be deleted
    metadata    JSONB,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE permissions (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource    TEXT        NOT NULL,  -- e.g. 'users', 'sessions'
    action      TEXT        NOT NULL,  -- e.g. 'read', 'write', 'delete'
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource, action)
);

CREATE TABLE role_permissions (
    role_id       UUID NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
    granted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    granted_by    UUID,   -- user_id of the granting admin
    PRIMARY KEY (role_id, permission_id)
);

-- ============================================================
-- SECTION 3 – USERS & AUTHENTICATION
-- ============================================================

CREATE TABLE users (
    id                    UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id             UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id        UUID        REFERENCES applications(id) ON DELETE SET NULL,
    organization_id       UUID        REFERENCES organizations(id) ON DELETE SET NULL,
    -- Encrypted PII – stored via pgcrypto, classification in pii_data_classifications
    email_encrypted       BYTEA       NOT NULL,
    email_hash            TEXT        NOT NULL,  -- SHA-256 for lookup
    phone_encrypted       BYTEA,
    phone_hash            TEXT,
    username              TEXT,
    -- Status & verification
    status                user_status NOT NULL DEFAULT 'pending_verification',
    email_verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    email_verified_at     TIMESTAMPTZ,
    phone_verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    phone_verified_at     TIMESTAMPTZ,
    -- MFA
    mfa_enabled           BOOLEAN     NOT NULL DEFAULT FALSE,
    mfa_enforced_at       TIMESTAMPTZ,
    -- Password
    last_password_changed_at TIMESTAMPTZ,
    -- Login tracking
    last_login_at         TIMESTAMPTZ,
    last_login_ip         INET,
    failed_login_count    INT         NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,
    -- GDPR
    gdpr_consent_at       TIMESTAMPTZ,
    data_deletion_requested_at TIMESTAMPTZ,
    -- Metadata
    metadata              JSONB,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at            TIMESTAMPTZ,
    UNIQUE (tenant_id, email_hash),
    UNIQUE (tenant_id, username)
);

CREATE TABLE user_profiles (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- Encrypted name fields (PII)
    first_name_encrypted  BYTEA,
    last_name_encrypted   BYTEA,
    display_name          TEXT,
    avatar_url            TEXT,
    -- Non-sensitive demographics
    birth_year        SMALLINT,          -- year only to avoid exact DOB
    gender            TEXT,
    locale            TEXT    DEFAULT 'en',
    timezone          TEXT    DEFAULT 'UTC',
    -- Address (encrypted)
    address_encrypted BYTEA,
    country_code      CHAR(2),           -- ISO-3166 alpha-2
    -- Preferences
    preferences       JSONB,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id)
);

CREATE TABLE user_credentials (
    id                  UUID            PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    credential_type     credential_type NOT NULL DEFAULT 'password',
    -- Password credential
    password_hash       TEXT,           -- bcrypt / argon2id hash
    -- Password history (hashes of previous N passwords)
    password_history    TEXT[]          NOT NULL DEFAULT '{}',
    -- Passkey / WebAuthn
    public_key          BYTEA,
    credential_id       TEXT,           -- WebAuthn credential ID (base64url)
    -- Magic link
    token_hash          TEXT,
    token_expires_at    TIMESTAMPTZ,
    -- Metadata
    is_primary          BOOLEAN         NOT NULL DEFAULT TRUE,
    last_used_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE user_roles (
    id              UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id         UUID        NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID        REFERENCES applications(id) ON DELETE SET NULL,
    expires_at      TIMESTAMPTZ,
    assigned_by     UUID,               -- admin user_id
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, role_id, application_id)
);

CREATE TABLE user_sessions (
    id               UUID           PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID           NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id   UUID           REFERENCES applications(id) ON DELETE SET NULL,
    status           session_status NOT NULL DEFAULT 'active',
    token_hash       TEXT           NOT NULL UNIQUE,  -- SHA-256 of session token
    refresh_token_hash TEXT,
    ip_address       INET,
    user_agent       TEXT,
    device_fingerprint_id UUID,     -- FK to device_fingerprints added later
    -- SSO federation
    sso_session_id   UUID,
    idp_session_id   TEXT,          -- IdP-side session ID
    -- Timestamps
    last_active_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    expires_at       TIMESTAMPTZ    NOT NULL,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    revoked_at       TIMESTAMPTZ
);

-- ============================================================
-- SECTION 4 – MFA
-- ============================================================

CREATE TABLE mfa_devices (
    id             UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id        UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id      UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    method         mfa_method_type   NOT NULL,
    name           TEXT,             -- user-supplied device name
    status         mfa_device_status NOT NULL DEFAULT 'pending_activation',
    -- TOTP
    totp_secret_encrypted  BYTEA,    -- AES-256 encrypted TOTP secret
    totp_issuer    TEXT,
    totp_algorithm TEXT    DEFAULT 'SHA1',
    totp_digits    SMALLINT DEFAULT 6,
    totp_period    SMALLINT DEFAULT 30,
    -- SMS / Email
    destination_encrypted BYTEA,     -- encrypted phone / email
    -- WebAuthn
    credential_id        TEXT,       -- base64url
    public_key_cbor      BYTEA,      -- COSE-encoded public key
    aaguid               TEXT,       -- authenticator AAGUID
    sign_count           BIGINT      DEFAULT 0,
    rp_id                TEXT,       -- relying party ID
    -- Push
    push_token_encrypted BYTEA,
    push_provider        TEXT,       -- 'fcm', 'apns', etc.
    -- Metadata
    last_used_at         TIMESTAMPTZ,
    verified_at          TIMESTAMPTZ,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_recovery_codes (
    id          UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    code_hash   TEXT        NOT NULL,   -- bcrypt hash of recovery code
    used        BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at     TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_challenges (
    id            UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id       UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id     UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id     UUID              REFERENCES mfa_devices(id) ON DELETE CASCADE,
    method        mfa_method_type   NOT NULL,
    challenge     TEXT              NOT NULL,  -- OTP / nonce sent to user
    is_verified   BOOLEAN           NOT NULL DEFAULT FALSE,
    expires_at    TIMESTAMPTZ       NOT NULL,
    verified_at   TIMESTAMPTZ,
    ip_address    INET,
    created_at    TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- ============================================================
-- SECTION 5 – OAUTH 2.0
-- ============================================================

CREATE TABLE oauth_scopes (
    id          UUID            PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id   UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name        TEXT            NOT NULL,  -- e.g. 'openid', 'read:users'
    description TEXT,
    is_default  BOOLEAN         NOT NULL DEFAULT FALSE,
    is_public   BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE oauth_authorization_codes (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id    UUID        NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id           UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash         TEXT        NOT NULL UNIQUE,  -- SHA-256 of code
    redirect_uri      TEXT        NOT NULL,
    scopes            TEXT[]      NOT NULL DEFAULT '{}',
    -- PKCE
    code_challenge        TEXT,
    code_challenge_method TEXT    CHECK (code_challenge_method IN ('S256', 'plain')),
    -- OIDC nonce
    nonce             TEXT,
    -- State
    state             TEXT,
    is_used           BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at        TIMESTAMPTZ NOT NULL,
    used_at           TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oauth_tokens (
    id                UUID             PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID             NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id    UUID             NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id           UUID             REFERENCES users(id) ON DELETE CASCADE,
    token_type        oauth_token_type NOT NULL,
    token_hash        TEXT             NOT NULL UNIQUE,
    status            oauth_token_status NOT NULL DEFAULT 'active',
    scopes            TEXT[]           NOT NULL DEFAULT '{}',
    -- Refresh token relationship
    parent_token_id   UUID             REFERENCES oauth_tokens(id) ON DELETE SET NULL,
    -- JWT claims (for opaque token lookup)
    claims            JSONB,
    -- Session binding
    session_id        UUID             REFERENCES user_sessions(id) ON DELETE SET NULL,
    -- Timing
    issued_at         TIMESTAMPTZ      NOT NULL DEFAULT now(),
    expires_at        TIMESTAMPTZ      NOT NULL,
    last_used_at      TIMESTAMPTZ,
    revoked_at        TIMESTAMPTZ,
    revocation_reason TEXT,
    -- Client credentials flow has no user
    client_ip         INET,
    created_at        TIMESTAMPTZ      NOT NULL DEFAULT now()
);

CREATE TABLE oauth_application_scopes (
    application_id UUID NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    scope_id       UUID NOT NULL REFERENCES oauth_scopes(id) ON DELETE CASCADE,
    PRIMARY KEY (application_id, scope_id)
);

-- ============================================================
-- SECTION 6 – IDENTITY PROVIDERS (IdP)
-- ============================================================

CREATE TABLE identity_providers (
    id               UUID       PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID       NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name             TEXT       NOT NULL,
    slug             TEXT       NOT NULL,
    provider_type    idp_type   NOT NULL,
    status           idp_status NOT NULL DEFAULT 'active',
    -- Generic OAuth / OIDC fields
    issuer_url       TEXT,
    authorization_endpoint TEXT,
    token_endpoint   TEXT,
    userinfo_endpoint TEXT,
    jwks_uri         TEXT,
    client_id        TEXT,
    client_secret_encrypted BYTEA,   -- AES-256 encrypted
    -- SAML specific
    entity_id        TEXT,
    metadata_url     TEXT,
    sso_url          TEXT,
    slo_url          TEXT,
    x509_cert        TEXT,
    -- Provisioning
    auto_provision   BOOLEAN    NOT NULL DEFAULT FALSE,
    sync_on_login    BOOLEAN    NOT NULL DEFAULT TRUE,
    default_role_id  UUID       REFERENCES roles(id) ON DELETE SET NULL,
    -- Attribute mapping stored as JSON: { "email": "user.email", ... }
    attribute_mapping JSONB,
    -- Logo / UI
    logo_url         TEXT,
    button_label     TEXT,
    -- Extra config (webhooks, custom headers, etc.)
    config           JSONB,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, slug)
);

CREATE TABLE saml_configurations (
    id                   UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id            UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id               UUID  NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    -- SP metadata
    sp_entity_id         TEXT  NOT NULL,
    sp_acs_url           TEXT  NOT NULL,   -- Assertion Consumer Service URL
    sp_slo_url           TEXT,
    sp_metadata_url      TEXT,
    -- Signing / Encryption
    sp_private_key_encrypted BYTEA,
    sp_certificate       TEXT,
    sign_requests        BOOLEAN NOT NULL DEFAULT TRUE,
    sign_assertions      BOOLEAN NOT NULL DEFAULT TRUE,
    encrypt_assertions   BOOLEAN NOT NULL DEFAULT FALSE,
    signature_algorithm  TEXT    NOT NULL DEFAULT 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256',
    digest_algorithm     TEXT    NOT NULL DEFAULT 'http://www.w3.org/2001/04/xmlenc#sha256',
    -- Name ID
    name_id_format       TEXT    NOT NULL DEFAULT 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
    -- Attribute mappings
    attribute_mapping    JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id)
);

CREATE TABLE oidc_configurations (
    id                   UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id            UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id               UUID  NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    discovery_url        TEXT,
    client_id            TEXT  NOT NULL,
    client_secret_encrypted BYTEA,
    response_type        TEXT  NOT NULL DEFAULT 'code',
    scopes               TEXT[] NOT NULL DEFAULT ARRAY['openid','profile','email'],
    -- Token validation
    id_token_signing_alg TEXT  NOT NULL DEFAULT 'RS256',
    -- PKCE
    use_pkce             BOOLEAN NOT NULL DEFAULT TRUE,
    pkce_method          TEXT    NOT NULL DEFAULT 'S256',
    -- Claims
    claims_mapping       JSONB,
    extra_params         JSONB,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id)
);

CREATE TABLE sso_sessions (
    id                 UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id          UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id            UUID              NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    idp_id             UUID              REFERENCES identity_providers(id) ON DELETE SET NULL,
    protocol           sso_protocol      NOT NULL,
    status             sso_session_status NOT NULL DEFAULT 'active',
    -- Federation
    idp_session_id     TEXT,
    idp_name_id        TEXT,
    -- Applications that joined this SSO session
    participating_apps UUID[]            NOT NULL DEFAULT '{}',
    -- Tokens / assertions
    id_token           TEXT,             -- raw JWT id_token from IdP
    saml_assertion_id  TEXT,
    -- Timing
    authenticated_at   TIMESTAMPTZ       NOT NULL DEFAULT now(),
    expires_at         TIMESTAMPTZ       NOT NULL,
    last_active_at     TIMESTAMPTZ       NOT NULL DEFAULT now(),
    logged_out_at      TIMESTAMPTZ,
    ip_address         INET,
    user_agent         TEXT,
    created_at         TIMESTAMPTZ       NOT NULL DEFAULT now()
);

-- ============================================================
-- SECTION 7 – FEDERATED IDENTITIES
-- ============================================================

CREATE TABLE federated_identities (
    id                  UUID                    PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id             UUID                    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    idp_id              UUID                    NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    status              federated_identity_status NOT NULL DEFAULT 'active',
    -- The subject identifier assigned by the external IdP
    subject             TEXT                    NOT NULL,
    -- Tokens from the IdP (encrypted)
    access_token_encrypted  BYTEA,
    refresh_token_encrypted BYTEA,
    token_expires_at    TIMESTAMPTZ,
    -- Profile snapshot from last login
    idp_profile         JSONB,
    -- Derived claims
    email               TEXT,
    name                TEXT,
    picture_url         TEXT,
    -- Timestamps
    last_login_at       TIMESTAMPTZ,
    linked_at           TIMESTAMPTZ             NOT NULL DEFAULT now(),
    unlinked_at         TIMESTAMPTZ,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, idp_id, subject)
);

CREATE TABLE linked_accounts (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    target_user_id   UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    -- e.g. 'same_person' | 'delegated_access'
    link_type        TEXT        NOT NULL DEFAULT 'same_person',
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, target_user_id)
);

-- ============================================================
-- SECTION 8 – LOCALIZATION
-- ============================================================

CREATE TABLE languages (
    id           UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    code         CHAR(5) NOT NULL UNIQUE,  -- BCP-47, e.g. 'en', 'pt-BR'
    name         TEXT  NOT NULL,
    native_name  TEXT  NOT NULL,
    is_rtl       BOOLEAN NOT NULL DEFAULT FALSE,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order   SMALLINT NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE timezones (
    id           UUID     PRIMARY KEY DEFAULT generate_uuid_v7(),
    name         TEXT     NOT NULL UNIQUE,   -- IANA, e.g. 'America/New_York'
    abbreviation TEXT,                        -- e.g. 'EST'
    utc_offset   INTERVAL NOT NULL,
    has_dst      BOOLEAN  NOT NULL DEFAULT FALSE,
    region       TEXT,
    is_active    BOOLEAN  NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_localization_preferences (
    id               UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID  NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    language_code    TEXT  NOT NULL DEFAULT 'en',
    timezone         TEXT  NOT NULL DEFAULT 'UTC',
    date_format      TEXT  NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format      TEXT  NOT NULL DEFAULT 'HH:mm',
    number_format    TEXT  NOT NULL DEFAULT '1,234.56',
    currency         CHAR(3) NOT NULL DEFAULT 'USD',    -- ISO-4217
    first_day_of_week SMALLINT NOT NULL DEFAULT 1,      -- 1=Monday, 7=Sunday
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id)
);

CREATE TABLE tenant_regional_settings (
    id                       UUID               PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id                UUID               NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    regulation               regulation_region  NOT NULL,
    data_residency           data_residency_region NOT NULL,
    -- Applicable regulations
    gdpr_enabled             BOOLEAN            NOT NULL DEFAULT FALSE,
    ccpa_enabled             BOOLEAN            NOT NULL DEFAULT FALSE,
    eidas_enabled            BOOLEAN            NOT NULL DEFAULT FALSE,
    -- Data-residency constraints
    restrict_cross_border    BOOLEAN            NOT NULL DEFAULT FALSE,
    allowed_transfer_regions data_residency_region[],
    -- Retention
    data_retention_days      INT                NOT NULL DEFAULT 365,
    consent_required         BOOLEAN            NOT NULL DEFAULT TRUE,
    created_at               TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at               TIMESTAMPTZ        NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, regulation)
);

CREATE TABLE ui_translations (
    id           UUID  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id    UUID  REFERENCES tenants(id) ON DELETE CASCADE,   -- NULL = global
    language_code TEXT NOT NULL,
    namespace    TEXT NOT NULL DEFAULT 'common',  -- e.g. 'auth', 'errors'
    key          TEXT NOT NULL,
    value        TEXT NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, language_code, namespace, key)
);

-- ============================================================
-- SECTION 9 – AUDIT & COMPLIANCE
-- ============================================================

CREATE TABLE audit_logs (
    id               UUID             PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID             NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_type       audit_event_type NOT NULL,
    severity         audit_severity   NOT NULL DEFAULT 'info',
    -- Actor
    actor_user_id    UUID             REFERENCES users(id) ON DELETE SET NULL,
    actor_type       TEXT             NOT NULL DEFAULT 'user',  -- 'user','service','system'
    -- Target resource
    resource_type    TEXT,
    resource_id      TEXT,
    -- Context
    application_id   UUID             REFERENCES applications(id) ON DELETE SET NULL,
    session_id       UUID,
    ip_address       INET,
    user_agent       TEXT,
    -- Geolocation (non-precise)
    country_code     CHAR(2),
    region_code      TEXT,
    -- Outcome
    outcome          TEXT             NOT NULL DEFAULT 'success',  -- 'success','failure'
    error_code       TEXT,
    error_message    TEXT,
    -- Payload (sanitised – no raw PII/secrets)
    metadata         JSONB,
    -- Tamper-evident chain
    previous_log_id  UUID             REFERENCES audit_logs(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ      NOT NULL DEFAULT now()
);

CREATE TABLE user_consents (
    id               UUID           PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id          UUID           NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id        UUID           NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    consent_type     consent_type   NOT NULL,
    status           consent_status NOT NULL DEFAULT 'pending',
    -- Versioned consent documents
    document_version TEXT           NOT NULL DEFAULT '1.0',
    document_url     TEXT,
    -- Evidence
    ip_address       INET,
    user_agent       TEXT,
    method           TEXT           NOT NULL DEFAULT 'explicit',  -- 'explicit','implied'
    -- Timestamps
    granted_at       TIMESTAMPTZ,
    withdrawn_at     TIMESTAMPTZ,
    expires_at       TIMESTAMPTZ,
    created_at       TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE TABLE data_retention_policies (
    id                UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id         UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    table_name        TEXT        NOT NULL,
    retention_days    INT         NOT NULL,
    -- Column and value for filtering rows to purge
    filter_column     TEXT        NOT NULL DEFAULT 'deleted_at',
    is_hard_delete    BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Regulation that mandates this policy
    regulation        pii_regulation,
    is_active         BOOLEAN     NOT NULL DEFAULT TRUE,
    last_run_at       TIMESTAMPTZ,
    next_run_at       TIMESTAMPTZ,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name)
);

CREATE TABLE pii_deletion_requests (
    id              UUID                    PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id       UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID                    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status          deletion_request_status NOT NULL DEFAULT 'pending',
    request_type    TEXT                    NOT NULL DEFAULT 'erasure',  -- 'erasure','portability','access'
    regulation      pii_regulation,
    -- Fulfilment
    requested_at    TIMESTAMPTZ             NOT NULL DEFAULT now(),
    deadline_at     TIMESTAMPTZ,            -- legal deadline (GDPR = 30 days)
    completed_at    TIMESTAMPTZ,
    failed_at       TIMESTAMPTZ,
    failure_reason  TEXT,
    -- Requestor details
    requested_by    UUID                    REFERENCES users(id) ON DELETE SET NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT now()
);

-- ============================================================
-- SECTION 10 – SECURITY
-- ============================================================

CREATE TABLE device_fingerprints (
    id                 UUID              PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id            UUID              REFERENCES users(id) ON DELETE CASCADE,
    tenant_id          UUID              NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    fingerprint_hash   TEXT              NOT NULL,  -- SHA-256 of raw fingerprint
    -- Device attributes (non-sensitive)
    device_type        TEXT,             -- 'desktop','mobile','tablet'
    os                 TEXT,
    os_version         TEXT,
    browser            TEXT,
    browser_version    TEXT,
    screen_resolution  TEXT,
    -- Trust
    trust_level        device_trust_level NOT NULL DEFAULT 'unknown',
    trusted_at         TIMESTAMPTZ,
    -- Geolocation (coarse)
    country_code       CHAR(2),
    city               TEXT,
    -- Metadata
    first_seen_at      TIMESTAMPTZ        NOT NULL DEFAULT now(),
    last_seen_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    seen_count         INT                NOT NULL DEFAULT 1,
    UNIQUE (tenant_id, fingerprint_hash)
);

-- Add FK from user_sessions to device_fingerprints
ALTER TABLE user_sessions
    ADD CONSTRAINT fk_session_device
    FOREIGN KEY (device_fingerprint_id) REFERENCES device_fingerprints(id) ON DELETE SET NULL;

CREATE TABLE security_events (
    id               UUID                  PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID                  NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id          UUID                  REFERENCES users(id) ON DELETE SET NULL,
    event_type       security_event_type   NOT NULL,
    risk_level       risk_level            NOT NULL DEFAULT 'low',
    status           security_event_status NOT NULL DEFAULT 'open',
    -- Detection details
    ip_address       INET,
    user_agent       TEXT,
    country_code     CHAR(2),
    -- Details
    description      TEXT,
    metadata         JSONB,
    -- Resolution
    resolved_by      UUID                  REFERENCES users(id) ON DELETE SET NULL,
    resolved_at      TIMESTAMPTZ,
    resolution_note  TEXT,
    created_at       TIMESTAMPTZ           NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ           NOT NULL DEFAULT now()
);

CREATE TABLE rate_limit_configs (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource         TEXT        NOT NULL,   -- e.g. 'login', 'password_reset'
    max_requests     INT         NOT NULL,
    window_sec       INT         NOT NULL,
    -- Scope: 'ip', 'user', 'tenant', 'app'
    scope            TEXT        NOT NULL DEFAULT 'ip',
    -- Action on limit exceeded
    action           TEXT        NOT NULL DEFAULT 'block',  -- 'block','captcha','delay'
    is_active        BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource, scope)
);

CREATE TABLE ip_allowlists (
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

-- ============================================================
-- SECTION 11 – PII & DATA CLASSIFICATION
-- ============================================================

CREATE TABLE pii_data_classifications (
    id               UUID               PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID               REFERENCES tenants(id) ON DELETE CASCADE,  -- NULL = global
    table_name       TEXT               NOT NULL,
    column_name      TEXT               NOT NULL,
    classification   pii_classification NOT NULL DEFAULT 'internal',
    regulations      pii_regulation[]   NOT NULL DEFAULT '{}',
    is_encrypted     BOOLEAN            NOT NULL DEFAULT FALSE,
    encryption_key_id TEXT,             -- reference to key management system
    notes            TEXT,
    created_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ        NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name, column_name)
);

CREATE TABLE api_keys (
    id               UUID        PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id   UUID        REFERENCES applications(id) ON DELETE SET NULL,
    user_id          UUID        REFERENCES users(id) ON DELETE SET NULL,
    name             TEXT        NOT NULL,
    key_hash         TEXT        NOT NULL UNIQUE,  -- SHA-256 of raw key
    key_prefix       CHAR(8)     NOT NULL,         -- first 8 chars for display
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

CREATE TABLE password_reset_tokens (
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

CREATE TABLE email_verification_tokens (
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
