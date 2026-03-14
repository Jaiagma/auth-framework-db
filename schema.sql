-- =============================================================================
-- schema.sql
-- Complete PostgreSQL schema for the multi-tenant authentication framework.
-- ALL primary keys and foreign keys use UUID v7 via uuid_generate_v7()
-- (defined in functions.sql and called via the DEFAULT expression).
-- =============================================================================

-- Ensure extensions and enums are loaded first (see extensions.sql, enums.sql).

-- =============================================================================
-- SECTION 1 – TENANTS & ORGANISATIONS
-- =============================================================================

CREATE TABLE tenants (
    id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    name                    TEXT        NOT NULL,
    slug                    TEXT        NOT NULL UNIQUE,
    display_name            TEXT,
    description             TEXT,
    status                  tenant_status NOT NULL DEFAULT 'pending_activation',
    plan                    tenant_plan   NOT NULL DEFAULT 'free',
    -- Branding
    logo_url                TEXT,
    primary_color           VARCHAR(7),
    login_url               TEXT,
    -- Contact
    support_email           TEXT,
    billing_email           TEXT,
    -- Regional
    default_language        VARCHAR(10)  NOT NULL DEFAULT 'en',
    default_timezone        TEXT         NOT NULL DEFAULT 'UTC',
    default_region          VARCHAR(10),
    -- Security settings (JSONB for flexibility)
    security_settings       JSONB        NOT NULL DEFAULT '{}',
    -- Rate limiting
    max_users               INT,
    max_applications        INT          DEFAULT 10,
    max_api_keys            INT          DEFAULT 50,
    -- Compliance
    data_residency_region   TEXT,
    applicable_regulations  regulation_type[]  DEFAULT '{}',
    -- Metadata
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

-- =============================================================================
-- SECTION 2 – USERS & CREDENTIALS
-- =============================================================================

CREATE TABLE users (
    id                          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id                   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- PII stored encrypted (see functions.sql encrypt_pii / decrypt_pii)
    email_encrypted             BYTEA       NOT NULL,
    email_hash                  TEXT        NOT NULL,   -- HMAC hash for lookups
    phone_encrypted             BYTEA,
    phone_hash                  TEXT,
    first_name_encrypted        BYTEA,
    last_name_encrypted         BYTEA,
    display_name                TEXT,
    avatar_url                  TEXT,
    -- Auth
    status                      user_status     NOT NULL DEFAULT 'pending_verification',
    role                        user_role       NOT NULL DEFAULT 'end_user',
    email_verified              BOOLEAN         NOT NULL DEFAULT FALSE,
    email_verified_at           TIMESTAMPTZ,
    phone_verified              BOOLEAN         NOT NULL DEFAULT FALSE,
    phone_verified_at           TIMESTAMPTZ,
    -- Locale
    language_code               VARCHAR(10)     NOT NULL DEFAULT 'en',
    timezone                    TEXT            NOT NULL DEFAULT 'UTC',
    -- Security
    failed_login_attempts       INT             NOT NULL DEFAULT 0,
    locked_until                TIMESTAMPTZ,
    last_login_at               TIMESTAMPTZ,
    last_login_ip               INET,
    password_changed_at         TIMESTAMPTZ,
    must_change_password        BOOLEAN         NOT NULL DEFAULT FALSE,
    -- Compliance
    gdpr_consent_given          BOOLEAN         NOT NULL DEFAULT FALSE,
    gdpr_consent_given_at       TIMESTAMPTZ,
    data_deletion_requested_at  TIMESTAMPTZ,
    -- Metadata
    external_id                 TEXT,           -- ID from external system
    metadata                    JSONB           NOT NULL DEFAULT '{}',
    created_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at                  TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deleted_at                  TIMESTAMPTZ,
    UNIQUE (tenant_id, email_hash)
);

CREATE TABLE user_passwords (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    password_hash   TEXT        NOT NULL,
    algorithm       password_hash_algorithm NOT NULL DEFAULT 'argon2id',
    salt            TEXT,
    iterations      INT,
    is_current      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ
);

CREATE TABLE user_roles (
    id          UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id   UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role        user_role   NOT NULL,
    granted_by  UUID        REFERENCES users(id),
    granted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ,
    UNIQUE (tenant_id, user_id, role)
);

-- =============================================================================
-- SECTION 3 – APPLICATIONS
-- =============================================================================

CREATE TABLE applications (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                TEXT        NOT NULL,
    slug                TEXT        NOT NULL,
    description         TEXT,
    logo_url            TEXT,
    -- OAuth client details
    client_id           TEXT        NOT NULL UNIQUE DEFAULT gen_random_uuid()::TEXT,
    client_secret_hash  TEXT,
    client_type         oauth_client_type NOT NULL DEFAULT 'confidential',
    -- Allowed redirect URIs (stored as JSONB array)
    redirect_uris       JSONB       NOT NULL DEFAULT '[]',
    post_logout_uris    JSONB       NOT NULL DEFAULT '[]',
    allowed_origins     JSONB       NOT NULL DEFAULT '[]',
    -- Grant types allowed for this app
    allowed_grant_types oauth_grant_type[] NOT NULL DEFAULT '{authorization_code}',
    -- Token lifetimes (seconds)
    access_token_ttl    INT         NOT NULL DEFAULT 3600,
    refresh_token_ttl   INT         NOT NULL DEFAULT 2592000,
    id_token_ttl        INT         NOT NULL DEFAULT 3600,
    -- App settings
    require_pkce        BOOLEAN     NOT NULL DEFAULT TRUE,
    is_first_party      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    metadata            JSONB       NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, slug)
);

-- =============================================================================
-- SECTION 4 – MFA
-- =============================================================================

CREATE TABLE mfa_devices (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    method          mfa_method  NOT NULL,
    status          mfa_status  NOT NULL DEFAULT 'pending',
    name            TEXT,
    -- TOTP / HOTP
    secret_encrypted BYTEA,
    -- WebAuthn
    credential_id   TEXT,
    public_key      TEXT,
    sign_count      BIGINT,
    aaguid          TEXT,
    -- SMS / Email
    delivery_address_encrypted BYTEA,
    -- Push
    push_token_encrypted BYTEA,
    device_platform TEXT,
    -- Metadata
    last_used_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_recovery_codes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    code_hash       TEXT        NOT NULL,
    used            BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mfa_challenges (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_id       UUID        REFERENCES mfa_devices(id),
    method          mfa_method  NOT NULL,
    challenge_data  JSONB       NOT NULL DEFAULT '{}',
    verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 5 – SESSIONS
-- =============================================================================

CREATE TABLE sessions (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID        REFERENCES applications(id),
    status              session_status NOT NULL DEFAULT 'active',
    -- Token
    session_token_hash  TEXT        NOT NULL UNIQUE,
    refresh_token_hash  TEXT        UNIQUE,
    -- Auth context
    auth_methods        auth_method[] NOT NULL DEFAULT '{}',
    mfa_verified        BOOLEAN     NOT NULL DEFAULT FALSE,
    mfa_device_id       UUID        REFERENCES mfa_devices(id),
    -- Client info
    ip_address          INET,
    user_agent          TEXT,
    device_id           UUID,       -- FK set after devices table
    -- Geolocation
    country_code        VARCHAR(2),
    region              TEXT,
    city                TEXT,
    -- Timing
    last_activity_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

-- =============================================================================
-- SECTION 6 – DEVICES
-- =============================================================================

CREATE TABLE devices (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id             UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    device_type         device_type     NOT NULL DEFAULT 'unknown',
    trust_status        device_trust_status NOT NULL DEFAULT 'untrusted',
    -- Fingerprint
    fingerprint_hash    TEXT            NOT NULL,
    -- Browser / OS info
    user_agent          TEXT,
    browser             TEXT,
    browser_version     TEXT,
    os                  TEXT,
    os_version          TEXT,
    -- Network
    last_ip             INET,
    -- Naming
    friendly_name       TEXT,
    -- Trusted device token (hashed)
    trust_token_hash    TEXT,
    trusted_at          TIMESTAMPTZ,
    trusted_until       TIMESTAMPTZ,
    last_seen_at        TIMESTAMPTZ     NOT NULL DEFAULT now(),
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

-- Back-fill FK on sessions.device_id
ALTER TABLE sessions
    ADD CONSTRAINT fk_sessions_device
    FOREIGN KEY (device_id) REFERENCES devices(id) ON DELETE SET NULL;

-- =============================================================================
-- SECTION 7 – OAUTH 2.0 / OIDC
-- =============================================================================

CREATE TABLE oauth_scopes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name            TEXT        NOT NULL,
    description     TEXT,
    is_default      BOOLEAN     NOT NULL DEFAULT FALSE,
    is_public       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, name)
);

CREATE TABLE application_scopes (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    application_id  UUID        NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    scope_id        UUID        NOT NULL REFERENCES oauth_scopes(id) ON DELETE CASCADE,
    UNIQUE (application_id, scope_id)
);

CREATE TABLE oauth_authorization_codes (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID        NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_hash           TEXT        NOT NULL UNIQUE,
    scopes              TEXT[]      NOT NULL DEFAULT '{}',
    redirect_uri        TEXT        NOT NULL,
    -- PKCE
    code_challenge      TEXT,
    code_challenge_method TEXT,
    -- OIDC nonce
    nonce               TEXT,
    state               TEXT,
    -- Status
    used                BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at             TIMESTAMPTZ,
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE oauth_tokens (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID            NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    user_id             UUID            REFERENCES users(id) ON DELETE CASCADE,
    session_id          UUID            REFERENCES sessions(id) ON DELETE CASCADE,
    token_type          oauth_token_type    NOT NULL,
    token_hash          TEXT            NOT NULL UNIQUE,
    scopes              TEXT[]          NOT NULL DEFAULT '{}',
    grant_type          oauth_grant_type    NOT NULL,
    status              oauth_token_status  NOT NULL DEFAULT 'active',
    -- JWT claims (for reference / introspection)
    claims              JSONB           NOT NULL DEFAULT '{}',
    -- Expiry
    expires_at          TIMESTAMPTZ     NOT NULL,
    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE TABLE oauth_refresh_tokens (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    access_token_id     UUID        NOT NULL REFERENCES oauth_tokens(id) ON DELETE CASCADE,
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash          TEXT        NOT NULL UNIQUE,
    rotation_count      INT         NOT NULL DEFAULT 0,
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 8 – API KEYS
-- =============================================================================

CREATE TABLE api_keys (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID            REFERENCES applications(id) ON DELETE CASCADE,
    created_by          UUID            NOT NULL REFERENCES users(id),
    name                TEXT            NOT NULL,
    key_prefix          VARCHAR(10)     NOT NULL,
    key_hash            TEXT            NOT NULL UNIQUE,
    scopes              TEXT[]          NOT NULL DEFAULT '{}',
    status              api_key_status  NOT NULL DEFAULT 'active',
    last_used_at        TIMESTAMPTZ,
    last_used_ip        INET,
    expires_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    revoked_at          TIMESTAMPTZ
);

-- =============================================================================
-- SECTION 9 – IDENTITY PROVIDERS (IdP)
-- =============================================================================

CREATE TABLE identity_providers (
    id                  UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name                TEXT            NOT NULL,
    display_name        TEXT,
    logo_url            TEXT,
    provider_type       idp_provider_type NOT NULL,
    protocol            idp_protocol    NOT NULL,
    status              idp_status      NOT NULL DEFAULT 'pending_configuration',
    -- Configuration stored as encrypted JSONB
    config_encrypted    BYTEA,
    -- Attribute mapping
    attribute_mapping   JSONB           NOT NULL DEFAULT '{}',
    -- User provisioning
    auto_provision_users BOOLEAN        NOT NULL DEFAULT FALSE,
    default_role        user_role       NOT NULL DEFAULT 'end_user',
    -- Order / priority
    display_order       INT             NOT NULL DEFAULT 0,
    is_default          BOOLEAN         NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- OIDC-specific configuration
CREATE TABLE oidc_configurations (
    id                      UUID    PRIMARY KEY DEFAULT uuid_generate_v7(),
    provider_id             UUID    NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE UNIQUE,
    tenant_id               UUID    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    issuer_url              TEXT    NOT NULL,
    authorization_endpoint  TEXT    NOT NULL,
    token_endpoint          TEXT    NOT NULL,
    userinfo_endpoint       TEXT,
    jwks_uri                TEXT    NOT NULL,
    end_session_endpoint    TEXT,
    client_id               TEXT    NOT NULL,
    client_secret_encrypted BYTEA,
    scopes                  TEXT[]  NOT NULL DEFAULT '{openid,profile,email}',
    response_type           TEXT    NOT NULL DEFAULT 'code',
    pkce_required           BOOLEAN NOT NULL DEFAULT TRUE,
    -- Discovery document cached
    discovery_document      JSONB,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- SAML 2.0-specific configuration
CREATE TABLE saml_configurations (
    id                      UUID    PRIMARY KEY DEFAULT uuid_generate_v7(),
    provider_id             UUID    NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE UNIQUE,
    tenant_id               UUID    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    -- SP (us)
    sp_entity_id            TEXT    NOT NULL,
    sp_acs_url              TEXT    NOT NULL,
    sp_slo_url              TEXT,
    sp_certificate          TEXT,
    sp_private_key_encrypted BYTEA,
    -- IdP (them)
    idp_entity_id           TEXT    NOT NULL,
    idp_sso_url             TEXT    NOT NULL,
    idp_slo_url             TEXT,
    idp_certificate         TEXT    NOT NULL,
    -- Settings
    name_id_format          TEXT    NOT NULL DEFAULT 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress',
    sign_requests           BOOLEAN NOT NULL DEFAULT TRUE,
    sign_assertions         BOOLEAN NOT NULL DEFAULT TRUE,
    encrypt_assertions      BOOLEAN NOT NULL DEFAULT FALSE,
    default_relay_state     TEXT,
    binding                 saml_binding NOT NULL DEFAULT 'http_post',
    -- Metadata XML
    idp_metadata_xml        TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 10 – FEDERATED IDENTITIES & LINKED ACCOUNTS
-- =============================================================================

CREATE TABLE federated_identities (
    id                      UUID    PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id                 UUID    NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id               UUID    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    provider_id             UUID    NOT NULL REFERENCES identity_providers(id) ON DELETE CASCADE,
    -- External subject identifier
    external_subject        TEXT    NOT NULL,
    external_email_hash     TEXT,
    -- Tokens from IdP (encrypted)
    access_token_encrypted  BYTEA,
    refresh_token_encrypted BYTEA,
    id_token_encrypted      BYTEA,
    token_expires_at        TIMESTAMPTZ,
    -- Raw profile from IdP
    raw_profile             JSONB   NOT NULL DEFAULT '{}',
    -- Timestamps
    first_linked_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, provider_id, external_subject)
);

-- =============================================================================
-- SECTION 11 – SSO SESSIONS
-- =============================================================================

CREATE TABLE sso_sessions (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id             UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider_id         UUID        NOT NULL REFERENCES identity_providers(id),
    -- IdP session info
    idp_session_id      TEXT,
    -- Status
    status              sso_session_status NOT NULL DEFAULT 'active',
    -- SAML AuthnStatement
    session_index       TEXT,
    authn_context       TEXT,
    -- Auth info
    ip_address          INET,
    user_agent          TEXT,
    -- Timing
    expires_at          TIMESTAMPTZ NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    terminated_at       TIMESTAMPTZ
);

CREATE TABLE sso_session_applications (
    id              UUID    PRIMARY KEY DEFAULT uuid_generate_v7(),
    sso_session_id  UUID    NOT NULL REFERENCES sso_sessions(id) ON DELETE CASCADE,
    application_id  UUID    NOT NULL REFERENCES applications(id) ON DELETE CASCADE,
    session_id      UUID    REFERENCES sessions(id),
    joined_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (sso_session_id, application_id)
);

-- =============================================================================
-- SECTION 12 – LOCALIZATION
-- =============================================================================

CREATE TABLE languages (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            VARCHAR(10) NOT NULL UNIQUE,
    name            TEXT        NOT NULL,
    native_name     TEXT        NOT NULL,
    direction       VARCHAR(3)  NOT NULL DEFAULT 'ltr' CHECK (direction IN ('ltr','rtl')),
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE timezones (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    name            TEXT        NOT NULL UNIQUE,
    display_name    TEXT        NOT NULL,
    offset_seconds  INT         NOT NULL DEFAULT 0,
    region          TEXT,
    is_dst          BOOLEAN     NOT NULL DEFAULT FALSE,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE user_localization_preferences (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    language_id     UUID        REFERENCES languages(id),
    timezone_id     UUID        REFERENCES timezones(id),
    locale          VARCHAR(20),
    date_format     TEXT        NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format     TEXT        NOT NULL DEFAULT 'HH:mm:ss',
    currency_code   VARCHAR(3),
    number_format   TEXT        NOT NULL DEFAULT 'en-US',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE tenant_regional_settings (
    id                      UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id               UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    region_code             VARCHAR(10) NOT NULL,
    applicable_regulations  regulation_type[] NOT NULL DEFAULT '{}',
    data_residency_zone     TEXT,
    -- Login restrictions for this region
    allowed_auth_methods    auth_method[] NOT NULL DEFAULT '{}',
    require_mfa             BOOLEAN     NOT NULL DEFAULT FALSE,
    -- Localization defaults
    default_language_id     UUID        REFERENCES languages(id),
    default_timezone_id     UUID        REFERENCES timezones(id),
    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, region_code)
);

CREATE TABLE ui_translations (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID        REFERENCES tenants(id) ON DELETE CASCADE,
    language_id     UUID        NOT NULL REFERENCES languages(id),
    key             TEXT        NOT NULL,
    value           TEXT        NOT NULL,
    namespace       TEXT        NOT NULL DEFAULT 'auth',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, language_id, namespace, key)
);

-- =============================================================================
-- SECTION 13 – AUDIT LOGS
-- =============================================================================

CREATE TABLE audit_logs (
    id              UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID            REFERENCES users(id) ON DELETE SET NULL,
    actor_id        UUID            REFERENCES users(id) ON DELETE SET NULL,
    application_id  UUID            REFERENCES applications(id) ON DELETE SET NULL,
    session_id      UUID            REFERENCES sessions(id) ON DELETE SET NULL,
    action          audit_action    NOT NULL,
    resource_type   TEXT            NOT NULL,
    resource_id     UUID,
    -- Request context
    ip_address      INET,
    user_agent      TEXT,
    -- Data (old/new for UPDATE-type events)
    old_values      JSONB,
    new_values      JSONB,
    metadata        JSONB           NOT NULL DEFAULT '{}',
    -- Timing
    occurred_at     TIMESTAMPTZ     NOT NULL DEFAULT now()
) PARTITION BY RANGE (occurred_at);

-- Create initial monthly partitions (last month, current, next 3 months)
CREATE TABLE audit_logs_2025_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
CREATE TABLE audit_logs_2025_02 PARTITION OF audit_logs
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
CREATE TABLE audit_logs_2025_03 PARTITION OF audit_logs
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
CREATE TABLE audit_logs_2026_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE audit_logs_2026_02 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE audit_logs_2026_03 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE TABLE audit_logs_2026_04 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE audit_logs_2026_05 PARTITION OF audit_logs
    FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE audit_logs_default  PARTITION OF audit_logs DEFAULT;

-- =============================================================================
-- SECTION 14 – SECURITY EVENTS
-- =============================================================================

CREATE TABLE security_events (
    id              UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    user_id         UUID                    REFERENCES users(id) ON DELETE SET NULL,
    application_id  UUID                    REFERENCES applications(id) ON DELETE SET NULL,
    event_type      security_event_type     NOT NULL,
    severity        security_event_severity NOT NULL DEFAULT 'medium',
    description     TEXT,
    -- Context
    ip_address      INET,
    user_agent      TEXT,
    country_code    VARCHAR(2),
    -- Risk score 0-100
    risk_score      SMALLINT                CHECK (risk_score BETWEEN 0 AND 100),
    -- Resolution
    resolved        BOOLEAN                 NOT NULL DEFAULT FALSE,
    resolved_by     UUID                    REFERENCES users(id),
    resolved_at     TIMESTAMPTZ,
    -- Raw data
    metadata        JSONB                   NOT NULL DEFAULT '{}',
    occurred_at     TIMESTAMPTZ             NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 15 – GDPR / COMPLIANCE
-- =============================================================================

CREATE TABLE user_consents (
    id              UUID            PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID            NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    consent_type    consent_type    NOT NULL,
    status          consent_status  NOT NULL DEFAULT 'pending',
    version         TEXT            NOT NULL,
    given_at        TIMESTAMPTZ,
    withdrawn_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ,
    ip_address      INET,
    user_agent      TEXT,
    metadata        JSONB           NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    UNIQUE (user_id, tenant_id, consent_type, version)
);

CREATE TABLE data_retention_policies (
    id                  UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    resource_type       TEXT                    NOT NULL,
    retention_days      INT                     NOT NULL,
    action              retention_policy_type   NOT NULL DEFAULT 'delete',
    regulation          regulation_type,
    is_active           BOOLEAN                 NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ             NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, resource_type)
);

CREATE TABLE pii_deletion_requests (
    id              UUID                    PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID                    NOT NULL REFERENCES users(id),
    tenant_id       UUID                    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    requested_by    UUID                    REFERENCES users(id),
    status          data_deletion_status    NOT NULL DEFAULT 'requested',
    reason          TEXT,
    regulation      regulation_type,
    -- Verification
    verified_at     TIMESTAMPTZ,
    -- Processing
    scheduled_for   TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    failure_reason  TEXT,
    metadata        JSONB                   NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ             NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ             NOT NULL DEFAULT now()
);

CREATE TABLE data_export_requests (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    requested_by    UUID        REFERENCES users(id),
    status          TEXT        NOT NULL DEFAULT 'pending'
                                    CHECK (status IN ('pending','processing','ready','downloaded','expired','failed')),
    format          TEXT        NOT NULL DEFAULT 'json' CHECK (format IN ('json','csv','xml')),
    download_url    TEXT,
    download_token_hash TEXT,
    expires_at      TIMESTAMPTZ,
    completed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 16 – DATA CLASSIFICATION & PII REGISTRY
-- =============================================================================

CREATE TABLE pii_field_registry (
    id                  UUID                PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID                REFERENCES tenants(id) ON DELETE CASCADE,
    table_name          TEXT                NOT NULL,
    column_name         TEXT                NOT NULL,
    classification      data_classification NOT NULL,
    description         TEXT,
    encryption_required BOOLEAN             NOT NULL DEFAULT TRUE,
    applicable_regulations regulation_type[] NOT NULL DEFAULT '{}',
    created_at          TIMESTAMPTZ         NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, table_name, column_name)
);

-- =============================================================================
-- SECTION 17 – PASSWORD RESET & MAGIC LINKS
-- =============================================================================

CREATE TABLE password_reset_tokens (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash      TEXT        NOT NULL UNIQUE,
    used            BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    ip_address      INET,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE magic_links (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID        REFERENCES applications(id),
    token_hash      TEXT        NOT NULL UNIQUE,
    redirect_url    TEXT,
    used            BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    ip_address      INET,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 18 – EMAIL VERIFICATION
-- =============================================================================

CREATE TABLE email_verification_tokens (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    token_hash      TEXT        NOT NULL UNIQUE,
    email_hash      TEXT        NOT NULL,
    used            BOOLEAN     NOT NULL DEFAULT FALSE,
    used_at         TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 19 – RATE LIMITING & IP MANAGEMENT
-- =============================================================================

CREATE TABLE ip_allowlist (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id  UUID        REFERENCES applications(id) ON DELETE CASCADE,
    cidr            CIDR        NOT NULL,
    description     TEXT,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by      UUID        REFERENCES users(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ip_blocklist (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id       UUID        REFERENCES tenants(id) ON DELETE CASCADE,
    cidr            CIDR        NOT NULL,
    reason          TEXT        NOT NULL,
    added_by        UUID        REFERENCES users(id),
    expires_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
-- SECTION 20 – WEBHOOK CONFIGURATIONS
-- =============================================================================

CREATE TABLE webhooks (
    id                  UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    tenant_id           UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    application_id      UUID        REFERENCES applications(id) ON DELETE CASCADE,
    url                 TEXT        NOT NULL,
    secret_hash         TEXT,
    events              TEXT[]      NOT NULL DEFAULT '{}',
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    failure_count       INT         NOT NULL DEFAULT 0,
    last_triggered_at   TIMESTAMPTZ,
    last_failure_at     TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE webhook_deliveries (
    id              UUID        PRIMARY KEY DEFAULT uuid_generate_v7(),
    webhook_id      UUID        NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
    tenant_id       UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    event_type      TEXT        NOT NULL,
    payload         JSONB       NOT NULL DEFAULT '{}',
    response_status INT,
    response_body   TEXT,
    duration_ms     INT,
    success         BOOLEAN     NOT NULL DEFAULT FALSE,
    attempt         INT         NOT NULL DEFAULT 1,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
