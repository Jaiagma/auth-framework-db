-- ============================================================
-- views.sql
-- Database views for common queries in the multi-tenant
-- authentication framework.
--
-- Prerequisites: enums.sql + schema.sql must be run first.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. v_active_users
--    Active, non-deleted users with their tenant slug.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_active_users AS
SELECT
    u.id,
    u.tenant_id,
    t.slug          AS tenant_slug,
    t.name          AS tenant_name,
    u.username,
    u.email_hash,
    u.status,
    u.email_verified,
    u.phone_verified,
    u.mfa_enabled,
    u.last_login_at,
    u.last_login_ip,
    u.failed_login_count,
    u.created_at
FROM users u
JOIN tenants t ON t.id = u.tenant_id
WHERE u.deleted_at IS NULL
  AND u.status     = 'active';

COMMENT ON VIEW v_active_users IS
    'Active, non-deleted users joined with their tenant. '
    'Does NOT expose encrypted PII columns.';

-- ────────────────────────────────────────────────────────────
-- 2. v_user_mfa_status
--    Per-user MFA summary: enrolled methods and device count.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_user_mfa_status AS
SELECT
    u.id              AS user_id,
    u.tenant_id,
    u.mfa_enabled,
    COUNT(d.id)       AS device_count,
    ARRAY_AGG(DISTINCT d.method ORDER BY d.method)
                      FILTER (WHERE d.id IS NOT NULL AND d.status = 'active')
                      AS active_methods,
    MAX(d.last_used_at) AS mfa_last_used_at,
    (SELECT COUNT(*) FROM mfa_recovery_codes rc
     WHERE rc.user_id = u.id AND rc.used = FALSE)
                      AS unused_recovery_codes
FROM users u
LEFT JOIN mfa_devices d
    ON d.user_id = u.id AND d.status = 'active'
WHERE u.deleted_at IS NULL
GROUP BY u.id, u.tenant_id, u.mfa_enabled;

COMMENT ON VIEW v_user_mfa_status IS
    'MFA enrollment summary per user, including method list and unused recovery codes.';

-- ────────────────────────────────────────────────────────────
-- 3. v_active_sessions
--    Active sessions with user and application context.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_active_sessions AS
SELECT
    s.id                AS session_id,
    s.user_id,
    s.tenant_id,
    t.slug              AS tenant_slug,
    s.application_id,
    a.name              AS application_name,
    s.status,
    s.ip_address,
    s.user_agent,
    s.last_active_at,
    s.expires_at,
    s.created_at,
    s.sso_session_id,
    df.trust_level      AS device_trust_level,
    df.device_type,
    df.os,
    df.browser
FROM user_sessions s
JOIN tenants t  ON t.id = s.tenant_id
LEFT JOIN applications a  ON a.id = s.application_id
LEFT JOIN device_fingerprints df ON df.id = s.device_fingerprint_id
WHERE s.status     = 'active'
  AND s.expires_at > now();

COMMENT ON VIEW v_active_sessions IS
    'Active, non-expired sessions with device and application context.';

-- ────────────────────────────────────────────────────────────
-- 4. v_oauth_token_status
--    Token overview per application and user.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_oauth_token_status AS
SELECT
    ot.id,
    ot.tenant_id,
    ot.application_id,
    a.name         AS application_name,
    ot.user_id,
    ot.token_type,
    ot.status,
    ot.scopes,
    ot.issued_at,
    ot.expires_at,
    ot.last_used_at,
    ot.revoked_at,
    ot.revocation_reason,
    CASE
        WHEN ot.status = 'active' AND ot.expires_at < now() THEN TRUE
        ELSE FALSE
    END            AS is_effectively_expired
FROM oauth_tokens ot
JOIN applications a ON a.id = ot.application_id;

COMMENT ON VIEW v_oauth_token_status IS
    'OAuth tokens with application name and an effective expiry flag.';

-- ────────────────────────────────────────────────────────────
-- 5. v_user_consents
--    Consent status per user, including whether currently
--    active and the consent document version.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_user_consents AS
SELECT
    uc.id,
    uc.user_id,
    uc.tenant_id,
    uc.consent_type,
    uc.status,
    uc.document_version,
    uc.granted_at,
    uc.withdrawn_at,
    uc.expires_at,
    CASE
        WHEN uc.status = 'granted'
         AND (uc.expires_at IS NULL OR uc.expires_at > now())
        THEN TRUE
        ELSE FALSE
    END AS is_active_consent
FROM user_consents uc;

COMMENT ON VIEW v_user_consents IS
    'User consents with a computed is_active_consent flag.';

-- ────────────────────────────────────────────────────────────
-- 6. v_tenant_security_overview
--    High-level security metrics per tenant.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_tenant_security_overview AS
SELECT
    t.id             AS tenant_id,
    t.slug           AS tenant_slug,
    t.name           AS tenant_name,
    COUNT(DISTINCT u.id)
        FILTER (WHERE u.deleted_at IS NULL)
                     AS total_users,
    COUNT(DISTINCT u.id)
        FILTER (WHERE u.status = 'active' AND u.deleted_at IS NULL)
                     AS active_users,
    COUNT(DISTINCT u.id)
        FILTER (WHERE u.mfa_enabled = TRUE AND u.deleted_at IS NULL)
                     AS mfa_enabled_users,
    COUNT(DISTINCT u.id)
        FILTER (WHERE u.status = 'locked')
                     AS locked_users,
    COUNT(DISTINCT se.id)
        FILTER (WHERE se.status = 'open' AND se.risk_level IN ('high','critical'))
                     AS open_high_risk_events,
    COUNT(DISTINCT s.id)
        FILTER (WHERE s.status = 'active' AND s.expires_at > now())
                     AS active_sessions,
    t.require_mfa,
    ts.sso_enabled,
    ts.gdpr_enabled
FROM tenants t
LEFT JOIN users u              ON u.tenant_id = t.id
LEFT JOIN security_events se   ON se.tenant_id = t.id
LEFT JOIN user_sessions s      ON s.tenant_id = t.id
LEFT JOIN tenant_settings ts   ON ts.tenant_id = t.id
WHERE t.deleted_at IS NULL
GROUP BY
    t.id, t.slug, t.name,
    t.require_mfa, ts.sso_enabled, ts.gdpr_enabled;

COMMENT ON VIEW v_tenant_security_overview IS
    'Aggregated security statistics per tenant.';

-- ────────────────────────────────────────────────────────────
-- 7. v_idp_federation_summary
--    Identity provider configuration with federated identity
--    link counts.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_idp_federation_summary AS
SELECT
    idp.id            AS idp_id,
    idp.tenant_id,
    idp.name          AS idp_name,
    idp.provider_type,
    idp.status,
    COUNT(fi.id)      AS total_linked_identities,
    COUNT(fi.id)
        FILTER (WHERE fi.status = 'active')
                      AS active_linked_identities,
    MAX(fi.last_login_at)
                      AS last_federation_login
FROM identity_providers idp
LEFT JOIN federated_identities fi ON fi.idp_id = idp.id
GROUP BY
    idp.id, idp.tenant_id, idp.name, idp.provider_type, idp.status;

COMMENT ON VIEW v_idp_federation_summary IS
    'Identity provider summary including the count of linked external accounts.';

-- ────────────────────────────────────────────────────────────
-- 8. v_pending_deletion_requests
--    GDPR deletion requests that are overdue or approaching
--    their legal deadline.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_pending_deletion_requests AS
SELECT
    dr.id,
    dr.tenant_id,
    dr.user_id,
    dr.status,
    dr.request_type,
    dr.regulation,
    dr.requested_at,
    dr.deadline_at,
    CASE
        WHEN dr.deadline_at < now() THEN 'overdue'
        WHEN dr.deadline_at < now() + INTERVAL '7 days' THEN 'due_soon'
        ELSE 'on_track'
    END                   AS urgency,
    now() - dr.requested_at AS age
FROM pii_deletion_requests dr
WHERE dr.status IN ('pending', 'in_progress');

COMMENT ON VIEW v_pending_deletion_requests IS
    'Pending GDPR/PII deletion requests with urgency classification.';

-- ────────────────────────────────────────────────────────────
-- 9. v_audit_recent_failures
--    Last 1000 failed authentication events across all
--    tenants (useful for SIEM / alerting pipelines).
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_audit_recent_failures AS
SELECT
    al.id,
    al.tenant_id,
    al.event_type,
    al.severity,
    al.actor_user_id,
    al.ip_address,
    al.user_agent,
    al.country_code,
    al.error_code,
    al.error_message,
    al.created_at
FROM audit_logs al
WHERE al.outcome  = 'failure'
  AND al.event_type IN (
      'login_failure',
      'mfa_failed',
      'brute_force_detected',
      'rate_limit_exceeded',
      'ip_blocked'
  )
ORDER BY al.created_at DESC
LIMIT 1000;

COMMENT ON VIEW v_audit_recent_failures IS
    'Recent authentication failures ordered by time (max 1000 rows).';

-- ────────────────────────────────────────────────────────────
-- 10. v_application_oauth_summary
--     OAuth usage statistics per application.
-- ────────────────────────────────────────────────────────────
CREATE VIEW v_application_oauth_summary AS
SELECT
    a.id              AS application_id,
    a.tenant_id,
    a.name            AS application_name,
    a.app_type,
    a.is_active,
    COUNT(ot.id)
        FILTER (WHERE ot.token_type = 'access_token' AND ot.status = 'active' AND ot.expires_at > now())
                      AS active_access_tokens,
    COUNT(ot.id)
        FILTER (WHERE ot.token_type = 'refresh_token' AND ot.status = 'active')
                      AS active_refresh_tokens,
    COUNT(DISTINCT ot.user_id)
        FILTER (WHERE ot.status = 'active')
                      AS distinct_active_users,
    COUNT(ac.id)
        FILTER (WHERE ac.is_used = FALSE AND ac.expires_at > now())
                      AS pending_auth_codes,
    ARRAY_AGG(DISTINCT os.name ORDER BY os.name)
        FILTER (WHERE os.id IS NOT NULL)
                      AS registered_scopes
FROM applications a
LEFT JOIN oauth_tokens ot
    ON ot.application_id = a.id
LEFT JOIN oauth_authorization_codes ac
    ON ac.application_id = a.id
LEFT JOIN oauth_application_scopes oas
    ON oas.application_id = a.id
LEFT JOIN oauth_scopes os
    ON os.id = oas.scope_id
WHERE a.deleted_at IS NULL
GROUP BY
    a.id, a.tenant_id, a.name, a.app_type, a.is_active;

COMMENT ON VIEW v_application_oauth_summary IS
    'Per-application OAuth token and scope usage summary.';
