-- =============================================================================
-- views.sql
-- Common query views for the multi-tenant authentication framework.
-- All views respect RLS policies that are active on the underlying tables.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- v_active_users
-- Users that are active and not soft-deleted.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_users AS
SELECT
    u.id,
    u.tenant_id,
    u.display_name,
    u.status,
    u.role,
    u.email_verified,
    u.phone_verified,
    u.language_code,
    u.timezone,
    u.last_login_at,
    u.failed_login_attempts,
    u.gdpr_consent_given,
    u.created_at,
    u.updated_at
FROM users u
WHERE u.deleted_at IS NULL
  AND u.status     = 'active';

COMMENT ON VIEW v_active_users IS
    'Active, non-deleted users across all tenants (filtered further by RLS).';

-- ---------------------------------------------------------------------------
-- v_user_sessions
-- Active sessions enriched with basic user info.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_sessions AS
SELECT
    s.id              AS session_id,
    s.tenant_id,
    s.user_id,
    u.display_name    AS user_display_name,
    u.role            AS user_role,
    s.application_id,
    a.name            AS application_name,
    s.status,
    s.auth_methods,
    s.mfa_verified,
    s.ip_address,
    s.country_code,
    s.last_activity_at,
    s.expires_at,
    s.created_at
FROM sessions s
JOIN users        u ON u.id = s.user_id
LEFT JOIN applications a ON a.id = s.application_id
WHERE s.status = 'active'
  AND s.expires_at > now();

COMMENT ON VIEW v_user_sessions IS
    'Currently active, non-expired sessions with user and application context.';

-- ---------------------------------------------------------------------------
-- v_user_mfa_status
-- MFA enrollment summary per user.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_mfa_status AS
SELECT
    u.id          AS user_id,
    u.tenant_id,
    u.display_name,
    fn_user_has_mfa(u.id)                                           AS mfa_enrolled,
    count(DISTINCT md.id) FILTER (WHERE md.status = 'active')       AS active_device_count,
    count(DISTINCT md.id) FILTER (WHERE md.method = 'totp'
                                    AND md.status = 'active')       AS totp_count,
    count(DISTINCT md.id) FILTER (WHERE md.method = 'webauthn'
                                    AND md.status = 'active')       AS webauthn_count,
    count(DISTINCT md.id) FILTER (WHERE md.method = 'sms'
                                    AND md.status = 'active')       AS sms_count,
    count(DISTINCT rc.id) FILTER (WHERE rc.used = FALSE)            AS recovery_codes_remaining,
    max(md.last_used_at)                                            AS last_mfa_used_at
FROM users u
LEFT JOIN mfa_devices        md ON md.user_id = u.id
LEFT JOIN mfa_recovery_codes rc ON rc.user_id = u.id
WHERE u.deleted_at IS NULL
GROUP BY u.id, u.tenant_id, u.display_name;

COMMENT ON VIEW v_user_mfa_status IS
    'MFA enrollment summary per user including device count and recovery code availability.';

-- ---------------------------------------------------------------------------
-- v_oauth_token_status
-- Active OAuth tokens with app and user context.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_oauth_token_status AS
SELECT
    t.id              AS token_id,
    t.tenant_id,
    t.application_id,
    a.name            AS application_name,
    t.user_id,
    u.display_name    AS user_display_name,
    t.token_type,
    t.grant_type,
    t.scopes,
    t.status,
    t.expires_at,
    t.created_at
FROM oauth_tokens t
JOIN applications a ON a.id = t.application_id
LEFT JOIN users   u ON u.id = t.user_id
WHERE t.status = 'active'
  AND t.expires_at > now();

COMMENT ON VIEW v_oauth_token_status IS
    'Active, non-expired OAuth tokens with application and user context.';

-- ---------------------------------------------------------------------------
-- v_tenant_idp_summary
-- Identity provider summary per tenant.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_tenant_idp_summary AS
SELECT
    idp.tenant_id,
    t.name        AS tenant_name,
    idp.id        AS provider_id,
    idp.name      AS provider_name,
    idp.provider_type,
    idp.protocol,
    idp.status,
    idp.auto_provision_users,
    count(fi.id)  AS federated_identity_count,
    idp.created_at
FROM identity_providers idp
JOIN tenants t ON t.id = idp.tenant_id
LEFT JOIN federated_identities fi ON fi.provider_id = idp.id
GROUP BY idp.tenant_id, t.name, idp.id, idp.name,
         idp.provider_type, idp.protocol, idp.status,
         idp.auto_provision_users, idp.created_at;

COMMENT ON VIEW v_tenant_idp_summary IS
    'Identity provider configuration summary with linked identity counts.';

-- ---------------------------------------------------------------------------
-- v_user_consent_summary
-- Consent status overview per user.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_user_consent_summary AS
SELECT
    uc.user_id,
    uc.tenant_id,
    u.display_name,
    count(*)  FILTER (WHERE uc.status = 'given')     AS consents_given,
    count(*)  FILTER (WHERE uc.status = 'withdrawn') AS consents_withdrawn,
    count(*)  FILTER (WHERE uc.status = 'pending')   AS consents_pending,
    bool_or(uc.consent_type = 'privacy_policy'
            AND uc.status   = 'given')               AS privacy_policy_accepted,
    bool_or(uc.consent_type = 'terms_of_service'
            AND uc.status   = 'given')               AS tos_accepted,
    max(uc.given_at)                                 AS last_consent_given_at,
    max(uc.withdrawn_at)                             AS last_consent_withdrawn_at
FROM user_consents uc
JOIN users u ON u.id = uc.user_id
GROUP BY uc.user_id, uc.tenant_id, u.display_name;

COMMENT ON VIEW v_user_consent_summary IS
    'Aggregated consent status per user covering all consent types.';

-- ---------------------------------------------------------------------------
-- v_audit_log_recent
-- Most recent 1000 audit entries per tenant (last 90 days).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_audit_log_recent AS
SELECT
    al.id,
    al.tenant_id,
    al.user_id,
    al.actor_id,
    al.action,
    al.resource_type,
    al.resource_id,
    al.ip_address,
    al.metadata,
    al.occurred_at
FROM audit_logs al
WHERE al.occurred_at > now() - INTERVAL '90 days'
ORDER BY al.occurred_at DESC;

COMMENT ON VIEW v_audit_log_recent IS
    'Audit log entries from the past 90 days, ordered newest first.';

-- ---------------------------------------------------------------------------
-- v_security_event_summary
-- Open security events grouped by tenant and severity.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_security_event_summary AS
SELECT
    se.tenant_id,
    t.name            AS tenant_name,
    se.severity,
    se.event_type,
    count(*)          AS event_count,
    avg(se.risk_score)::NUMERIC(5,2) AS avg_risk_score,
    max(se.occurred_at)              AS last_occurred_at
FROM security_events se
JOIN tenants t ON t.id = se.tenant_id
WHERE se.resolved = FALSE
GROUP BY se.tenant_id, t.name, se.severity, se.event_type
ORDER BY se.tenant_id, se.severity DESC, event_count DESC;

COMMENT ON VIEW v_security_event_summary IS
    'Open security events grouped by tenant, severity, and type.';

-- ---------------------------------------------------------------------------
-- v_tenant_overview
-- High-level tenant health dashboard.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_tenant_overview AS
SELECT
    t.id              AS tenant_id,
    t.name,
    t.slug,
    t.status,
    t.plan,
    t.default_language,
    t.default_timezone,
    count(DISTINCT u.id)   FILTER (WHERE u.deleted_at IS NULL
                                     AND u.status = 'active')     AS active_user_count,
    count(DISTINCT app.id) FILTER (WHERE app.is_active = TRUE)    AS active_app_count,
    count(DISTINCT idp.id) FILTER (WHERE idp.status   = 'active') AS active_idp_count,
    count(DISTINCT s.id)   FILTER (WHERE s.status = 'active'
                                     AND s.expires_at > now())    AS active_session_count,
    t.created_at
FROM tenants t
LEFT JOIN users              u   ON u.tenant_id   = t.id
LEFT JOIN applications       app ON app.tenant_id  = t.id
LEFT JOIN identity_providers idp ON idp.tenant_id  = t.id
LEFT JOIN sessions           s   ON s.tenant_id    = t.id
WHERE t.deleted_at IS NULL
GROUP BY t.id, t.name, t.slug, t.status, t.plan,
         t.default_language, t.default_timezone, t.created_at;

COMMENT ON VIEW v_tenant_overview IS
    'High-level per-tenant health dashboard with user, app, IdP, and session counts.';

-- ---------------------------------------------------------------------------
-- v_pii_deletion_queue
-- Pending and in-progress deletion requests due for processing.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pii_deletion_queue AS
SELECT
    dr.id           AS request_id,
    dr.tenant_id,
    dr.user_id,
    dr.status,
    dr.regulation,
    dr.scheduled_for,
    dr.created_at
FROM pii_deletion_requests dr
WHERE dr.status IN ('requested', 'in_progress')
  AND dr.scheduled_for <= now()
ORDER BY dr.scheduled_for ASC;

COMMENT ON VIEW v_pii_deletion_queue IS
    'PII deletion requests that are due for processing ordered by scheduled date.';

-- ---------------------------------------------------------------------------
-- v_application_oauth_summary
-- OAuth usage summary per application.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_application_oauth_summary AS
SELECT
    a.id                AS application_id,
    a.tenant_id,
    a.name              AS application_name,
    a.client_type,
    a.is_active,
    count(DISTINCT ot.id) FILTER (WHERE ot.status = 'active'
                                    AND ot.token_type = 'access_token') AS active_access_tokens,
    count(DISTINCT ot.id) FILTER (WHERE ot.token_type = 'refresh_token'
                                    AND ot.status = 'active')           AS active_refresh_tokens,
    count(DISTINCT ot.user_id)                                          AS distinct_users,
    max(ot.created_at)                                                  AS last_token_issued_at
FROM applications a
LEFT JOIN oauth_tokens ot ON ot.application_id = a.id
GROUP BY a.id, a.tenant_id, a.name, a.client_type, a.is_active;

COMMENT ON VIEW v_application_oauth_summary IS
    'OAuth token usage summary per application.';
