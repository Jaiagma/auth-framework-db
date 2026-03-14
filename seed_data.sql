-- =============================================================================
-- seed_data.sql
-- Reference / seed data for the multi-tenant authentication framework.
-- Includes: languages, timezones, OAuth scopes, IdP templates.
-- Note: All IDs use uuid_generate_v7() – they are inserted literally here
--       with gen_random_uuid() so the file can be executed standalone.
--       In production these values are stable and referenced by client apps.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Languages (ISO 639-1 codes)
-- ---------------------------------------------------------------------------
INSERT INTO languages (id, code, name, native_name, direction, is_active)
VALUES
    (gen_random_uuid(), 'en',    'English',              'English',              'ltr', TRUE),
    (gen_random_uuid(), 'es',    'Spanish',              'Español',              'ltr', TRUE),
    (gen_random_uuid(), 'fr',    'French',               'Français',             'ltr', TRUE),
    (gen_random_uuid(), 'de',    'German',               'Deutsch',              'ltr', TRUE),
    (gen_random_uuid(), 'pt',    'Portuguese',           'Português',            'ltr', TRUE),
    (gen_random_uuid(), 'pt-BR', 'Portuguese (Brazil)',  'Português (Brasil)',   'ltr', TRUE),
    (gen_random_uuid(), 'it',    'Italian',              'Italiano',             'ltr', TRUE),
    (gen_random_uuid(), 'nl',    'Dutch',                'Nederlands',           'ltr', TRUE),
    (gen_random_uuid(), 'pl',    'Polish',               'Polski',               'ltr', TRUE),
    (gen_random_uuid(), 'sv',    'Swedish',              'Svenska',              'ltr', TRUE),
    (gen_random_uuid(), 'da',    'Danish',               'Dansk',                'ltr', TRUE),
    (gen_random_uuid(), 'fi',    'Finnish',              'Suomi',                'ltr', TRUE),
    (gen_random_uuid(), 'nb',    'Norwegian Bokmål',     'Norsk bokmål',         'ltr', TRUE),
    (gen_random_uuid(), 'ru',    'Russian',              'Русский',              'ltr', TRUE),
    (gen_random_uuid(), 'uk',    'Ukrainian',            'Українська',           'ltr', TRUE),
    (gen_random_uuid(), 'cs',    'Czech',                'Čeština',              'ltr', TRUE),
    (gen_random_uuid(), 'ro',    'Romanian',             'Română',               'ltr', TRUE),
    (gen_random_uuid(), 'hu',    'Hungarian',            'Magyar',               'ltr', TRUE),
    (gen_random_uuid(), 'tr',    'Turkish',              'Türkçe',               'ltr', TRUE),
    (gen_random_uuid(), 'ja',    'Japanese',             '日本語',               'ltr', TRUE),
    (gen_random_uuid(), 'ko',    'Korean',               '한국어',               'ltr', TRUE),
    (gen_random_uuid(), 'zh-CN', 'Chinese (Simplified)', '中文（简体）',         'ltr', TRUE),
    (gen_random_uuid(), 'zh-TW', 'Chinese (Traditional)','中文（繁體）',         'ltr', TRUE),
    (gen_random_uuid(), 'ar',    'Arabic',               'العربية',              'rtl', TRUE),
    (gen_random_uuid(), 'he',    'Hebrew',               'עברית',                'rtl', TRUE),
    (gen_random_uuid(), 'fa',    'Persian',              'فارسی',                'rtl', TRUE),
    (gen_random_uuid(), 'hi',    'Hindi',                'हिन्दी',               'ltr', TRUE),
    (gen_random_uuid(), 'th',    'Thai',                 'ภาษาไทย',              'ltr', TRUE),
    (gen_random_uuid(), 'id',    'Indonesian',           'Bahasa Indonesia',     'ltr', TRUE),
    (gen_random_uuid(), 'ms',    'Malay',                'Bahasa Melayu',        'ltr', TRUE),
    (gen_random_uuid(), 'vi',    'Vietnamese',           'Tiếng Việt',           'ltr', TRUE)
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Timezones (representative subset of the IANA timezone database)
-- ---------------------------------------------------------------------------
INSERT INTO timezones (id, name, display_name, offset_seconds, region, is_active)
VALUES
    -- UTC
    (gen_random_uuid(), 'UTC',                    'UTC',                              0,         'Global', TRUE),
    -- Americas
    (gen_random_uuid(), 'America/New_York',        'Eastern Time (US & Canada)',    -18000,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Chicago',         'Central Time (US & Canada)',    -21600,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Denver',          'Mountain Time (US & Canada)',   -25200,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Los_Angeles',     'Pacific Time (US & Canada)',    -28800,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Anchorage',       'Alaska',                        -32400,    'Americas', TRUE),
    (gen_random_uuid(), 'Pacific/Honolulu',        'Hawaii',                        -36000,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Sao_Paulo',       'Brasilia',                      -10800,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Argentina/Buenos_Aires', 'Buenos Aires',           -10800,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Mexico_City',     'Mexico City',                   -21600,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Toronto',         'Eastern Time (Canada)',         -18000,    'Americas', TRUE),
    (gen_random_uuid(), 'America/Vancouver',       'Pacific Time (Canada)',         -28800,    'Americas', TRUE),
    -- Europe
    (gen_random_uuid(), 'Europe/London',           'London',                             0,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Dublin',           'Dublin',                             0,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Paris',            'Paris',                          3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Berlin',           'Berlin',                         3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Amsterdam',        'Amsterdam',                      3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Madrid',           'Madrid',                         3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Rome',             'Rome',                           3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Warsaw',           'Warsaw',                         3600,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Bucharest',        'Bucharest',                      7200,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Helsinki',         'Helsinki',                       7200,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Athens',           'Athens',                         7200,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Moscow',           'Moscow',                        10800,    'Europe',   TRUE),
    (gen_random_uuid(), 'Europe/Istanbul',         'Istanbul',                      10800,    'Europe',   TRUE),
    -- Asia / Pacific
    (gen_random_uuid(), 'Asia/Dubai',              'Abu Dhabi, Dubai',              14400,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Karachi',            'Karachi',                       18000,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Kolkata',            'Mumbai, Kolkata',               19800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Dhaka',              'Dhaka',                         21600,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Bangkok',            'Bangkok, Hanoi',                25200,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Singapore',          'Singapore',                     28800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Kuala_Lumpur',       'Kuala Lumpur',                  28800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Hong_Kong',          'Hong Kong',                     28800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Shanghai',           'Beijing, Shanghai',             28800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Taipei',             'Taipei',                        28800,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Tokyo',              'Tokyo, Osaka',                  32400,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Seoul',              'Seoul',                         32400,    'Asia',     TRUE),
    (gen_random_uuid(), 'Australia/Sydney',        'Sydney, Melbourne',             36000,    'Pacific',  TRUE),
    (gen_random_uuid(), 'Australia/Brisbane',      'Brisbane',                      36000,    'Pacific',  TRUE),
    (gen_random_uuid(), 'Australia/Perth',         'Perth',                         28800,    'Pacific',  TRUE),
    (gen_random_uuid(), 'Pacific/Auckland',        'Auckland',                      43200,    'Pacific',  TRUE),
    -- Africa / Middle East
    (gen_random_uuid(), 'Africa/Johannesburg',     'Johannesburg',                   7200,    'Africa',   TRUE),
    (gen_random_uuid(), 'Africa/Cairo',            'Cairo',                          7200,    'Africa',   TRUE),
    (gen_random_uuid(), 'Africa/Nairobi',          'Nairobi',                       10800,    'Africa',   TRUE),
    (gen_random_uuid(), 'Africa/Lagos',            'Lagos',                          3600,    'Africa',   TRUE),
    (gen_random_uuid(), 'Asia/Jerusalem',          'Jerusalem',                      7200,    'Asia',     TRUE),
    (gen_random_uuid(), 'Asia/Riyadh',             'Riyadh',                        10800,    'Asia',     TRUE)
ON CONFLICT (name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- System tenant (used for platform-level OAuth scopes)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_system_tenant_id UUID := '018f4d7e-7c00-7000-8000-000000000001'::UUID;
BEGIN
    INSERT INTO tenants (
        id, name, slug, display_name, status, plan,
        default_language, default_timezone,
        security_settings
    ) VALUES (
        v_system_tenant_id,
        'System',
        'system',
        'Platform System Tenant',
        'active',
        'enterprise',
        'en',
        'UTC',
        '{}'
    ) ON CONFLICT (slug) DO NOTHING;

    -- ---------------------------------------------------------------------------
    -- Standard OAuth 2.0 / OIDC scopes
    -- ---------------------------------------------------------------------------
    INSERT INTO oauth_scopes (id, tenant_id, name, description, is_default, is_public)
    VALUES
        (gen_random_uuid(), v_system_tenant_id, 'openid',
            'OpenID Connect identity token', TRUE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'profile',
            'User profile information (name, locale, picture)', FALSE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'email',
            'User email address', FALSE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'phone',
            'User phone number', FALSE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'address',
            'User postal address', FALSE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'offline_access',
            'Issue refresh tokens for offline access', FALSE, TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'roles',
            'User roles and permissions', FALSE, FALSE),
        (gen_random_uuid(), v_system_tenant_id, 'mfa',
            'MFA verification status', FALSE, FALSE),
        (gen_random_uuid(), v_system_tenant_id, 'tenant',
            'Tenant-level information', FALSE, FALSE)
    ON CONFLICT (tenant_id, name) DO NOTHING;
END
$$;

-- ---------------------------------------------------------------------------
-- Identity Provider templates (no tenant – global reference rows)
-- These serve as documentation / default configs; each tenant copies/extends them.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_system_tenant_id UUID := '018f4d7e-7c00-7000-8000-000000000001'::UUID;
BEGIN
    INSERT INTO identity_providers (
        id, tenant_id, name, display_name, logo_url,
        provider_type, protocol, status,
        attribute_mapping, auto_provision_users, default_role, display_order
    ) VALUES
    (
        gen_random_uuid(), v_system_tenant_id,
        'google', 'Sign in with Google',
        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
        'google', 'oidc', 'disabled',
        '{"sub":"external_subject","email":"email","name":"display_name","picture":"avatar_url"}',
        TRUE, 'end_user', 1
    ),
    (
        gen_random_uuid(), v_system_tenant_id,
        'github', 'Sign in with GitHub',
        'https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png',
        'github', 'oauth2', 'disabled',
        '{"id":"external_subject","email":"email","login":"display_name","avatar_url":"avatar_url"}',
        TRUE, 'end_user', 2
    ),
    (
        gen_random_uuid(), v_system_tenant_id,
        'microsoft', 'Sign in with Microsoft',
        'https://learn.microsoft.com/en-us/azure/active-directory/develop/media/howto-add-branding-in-apps/ms-symbollockup_mssymbol_19.png',
        'microsoft', 'oidc', 'disabled',
        '{"oid":"external_subject","email":"email","name":"display_name","preferred_username":"email"}',
        TRUE, 'end_user', 3
    ),
    (
        gen_random_uuid(), v_system_tenant_id,
        'auth0', 'Sign in with Auth0',
        NULL,
        'auth0', 'oidc', 'disabled',
        '{"sub":"external_subject","email":"email","name":"display_name","picture":"avatar_url"}',
        TRUE, 'end_user', 4
    ),
    (
        gen_random_uuid(), v_system_tenant_id,
        'okta', 'Sign in with Okta',
        NULL,
        'okta', 'oidc', 'disabled',
        '{"sub":"external_subject","email":"email","name":"display_name"}',
        TRUE, 'end_user', 5
    )
    ON CONFLICT DO NOTHING;
END
$$;

-- ---------------------------------------------------------------------------
-- Default data retention policies for system tenant
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_system_tenant_id UUID := '018f4d7e-7c00-7000-8000-000000000001'::UUID;
BEGIN
    INSERT INTO data_retention_policies
        (id, tenant_id, resource_type, retention_days, action, regulation, is_active)
    VALUES
        (gen_random_uuid(), v_system_tenant_id, 'audit_logs',          365,  'delete',    'gdpr', TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'sessions',             90,  'delete',    'gdpr', TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'security_events',     180,  'delete',    'gdpr', TRUE),
        (gen_random_uuid(), v_system_tenant_id, 'users',              2555,  'anonymize', 'gdpr', TRUE),  -- 7 years
        (gen_random_uuid(), v_system_tenant_id, 'oauth_tokens',         30,  'delete',    'gdpr', TRUE)
    ON CONFLICT (tenant_id, resource_type) DO NOTHING;
END
$$;

-- ---------------------------------------------------------------------------
-- UI translations – English baseline (auth namespace)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    v_lang_id UUID;
BEGIN
    SELECT id INTO v_lang_id FROM languages WHERE code = 'en' LIMIT 1;
    IF v_lang_id IS NULL THEN RETURN; END IF;

    INSERT INTO ui_translations (id, tenant_id, language_id, key, value, namespace)
    VALUES
        (gen_random_uuid(), NULL, v_lang_id, 'login.title',               'Sign in to your account',  'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'login.email_placeholder',   'Email address',             'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'login.password_placeholder','Password',                  'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'login.submit',              'Sign in',                   'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'login.forgot_password',     'Forgot your password?',     'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'login.register',            'Create an account',         'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'mfa.title',                 'Two-factor authentication', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'mfa.totp_prompt',           'Enter the 6-digit code from your authenticator app', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'mfa.sms_prompt',            'Enter the code sent to your phone', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'mfa.use_recovery_code',     'Use a recovery code',       'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'error.invalid_credentials', 'Invalid email or password', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'error.account_locked',      'Your account has been temporarily locked. Please try again later.', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'error.mfa_invalid',         'Invalid verification code', 'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'consent.title',             'Privacy & Consent',         'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'consent.accept_all',        'Accept all',                'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'consent.reject_optional',   'Reject optional cookies',   'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'logout.title',              'You have been signed out',  'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'oauth.authorize_title',     'Authorize Application',     'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'oauth.grant_access',        'Allow access',              'auth'),
        (gen_random_uuid(), NULL, v_lang_id, 'oauth.deny_access',         'Deny',                      'auth')
    ON CONFLICT (tenant_id, language_id, namespace, key) DO NOTHING;
END
$$;
