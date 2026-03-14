-- ============================================================
-- seed_data.sql
-- Reference / sample data for the multi-tenant authentication
-- framework.
--
-- Prerequisites: enums.sql + schema.sql must be run first.
-- This file is safe to run in both development and production
-- environments. It uses ON CONFLICT DO NOTHING so it is
-- idempotent.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. Languages (BCP-47 codes)
-- ────────────────────────────────────────────────────────────
INSERT INTO languages (code, name, native_name, is_rtl, is_active, sort_order) VALUES
    ('en',    'English',             'English',                 FALSE, TRUE, 1),
    ('en-US', 'English (US)',        'English (US)',            FALSE, TRUE, 2),
    ('en-GB', 'English (UK)',        'English (UK)',            FALSE, TRUE, 3),
    ('fr',    'French',              'Français',                FALSE, TRUE, 10),
    ('fr-FR', 'French (France)',     'Français (France)',       FALSE, TRUE, 11),
    ('de',    'German',              'Deutsch',                 FALSE, TRUE, 20),
    ('de-DE', 'German (Germany)',    'Deutsch (Deutschland)',   FALSE, TRUE, 21),
    ('es',    'Spanish',             'Español',                 FALSE, TRUE, 30),
    ('es-ES', 'Spanish (Spain)',     'Español (España)',        FALSE, TRUE, 31),
    ('es-MX', 'Spanish (Mexico)',    'Español (México)',        FALSE, TRUE, 32),
    ('pt',    'Portuguese',          'Português',               FALSE, TRUE, 40),
    ('pt-BR', 'Portuguese (Brazil)', 'Português (Brasil)',      FALSE, TRUE, 41),
    ('pt-PT', 'Portuguese (Portugal)','Português (Portugal)',   FALSE, TRUE, 42),
    ('it',    'Italian',             'Italiano',                FALSE, TRUE, 50),
    ('nl',    'Dutch',               'Nederlands',              FALSE, TRUE, 60),
    ('pl',    'Polish',              'Polski',                  FALSE, TRUE, 70),
    ('ru',    'Russian',             'Русский',                 FALSE, TRUE, 80),
    ('ja',    'Japanese',            '日本語',                  FALSE, TRUE, 90),
    ('zh',    'Chinese',             '中文',                    FALSE, TRUE, 100),
    ('zh-CN', 'Chinese (Simplified)','中文（简体）',             FALSE, TRUE, 101),
    ('zh-TW', 'Chinese (Traditional)','中文（繁體）',            FALSE, TRUE, 102),
    ('ko',    'Korean',              '한국어',                  FALSE, TRUE, 110),
    ('ar',    'Arabic',              'العربية',                  TRUE, TRUE, 120),
    ('he',    'Hebrew',              'עברית',                    TRUE, TRUE, 130),
    ('hi',    'Hindi',               'हिन्दी',                 FALSE, TRUE, 140),
    ('tr',    'Turkish',             'Türkçe',                  FALSE, TRUE, 150),
    ('sv',    'Swedish',             'Svenska',                 FALSE, TRUE, 160),
    ('da',    'Danish',              'Dansk',                   FALSE, TRUE, 170),
    ('fi',    'Finnish',             'Suomi',                   FALSE, TRUE, 180),
    ('nb',    'Norwegian Bokmål',    'Norsk Bokmål',            FALSE, TRUE, 190),
    ('cs',    'Czech',               'Čeština',                 FALSE, TRUE, 200),
    ('hu',    'Hungarian',           'Magyar',                  FALSE, TRUE, 210),
    ('ro',    'Romanian',            'Română',                  FALSE, TRUE, 220),
    ('uk',    'Ukrainian',           'Українська',              FALSE, TRUE, 230),
    ('id',    'Indonesian',          'Bahasa Indonesia',        FALSE, TRUE, 240),
    ('ms',    'Malay',               'Bahasa Melayu',           FALSE, TRUE, 250),
    ('th',    'Thai',                'ภาษาไทย',                FALSE, TRUE, 260),
    ('vi',    'Vietnamese',          'Tiếng Việt',              FALSE, TRUE, 270)
ON CONFLICT (code) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 2. Timezones (representative IANA names)
-- ────────────────────────────────────────────────────────────
INSERT INTO timezones (name, abbreviation, utc_offset, has_dst, region) VALUES
    ('UTC',                    'UTC',   '0 hours',     FALSE, 'Global'),
    ('America/New_York',       'EST',   '-5 hours',    TRUE,  'Americas'),
    ('America/Chicago',        'CST',   '-6 hours',    TRUE,  'Americas'),
    ('America/Denver',         'MST',   '-7 hours',    TRUE,  'Americas'),
    ('America/Los_Angeles',    'PST',   '-8 hours',    TRUE,  'Americas'),
    ('America/Anchorage',      'AKST',  '-9 hours',    TRUE,  'Americas'),
    ('Pacific/Honolulu',       'HST',   '-10 hours',   FALSE, 'Pacific'),
    ('America/Toronto',        'EST',   '-5 hours',    TRUE,  'Americas'),
    ('America/Vancouver',      'PST',   '-8 hours',    TRUE,  'Americas'),
    ('America/Sao_Paulo',      'BRT',   '-3 hours',    TRUE,  'Americas'),
    ('America/Mexico_City',    'CST',   '-6 hours',    TRUE,  'Americas'),
    ('America/Buenos_Aires',   'ART',   '-3 hours',    FALSE, 'Americas'),
    ('America/Bogota',         'COT',   '-5 hours',    FALSE, 'Americas'),
    ('America/Lima',           'PET',   '-5 hours',    FALSE, 'Americas'),
    ('Europe/London',          'GMT',   '0 hours',     TRUE,  'Europe'),
    ('Europe/Paris',           'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Berlin',          'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Madrid',          'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Rome',            'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Amsterdam',       'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Brussels',        'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Warsaw',          'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Stockholm',       'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Oslo',            'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Copenhagen',      'CET',   '1 hour',      TRUE,  'Europe'),
    ('Europe/Helsinki',        'EET',   '2 hours',     TRUE,  'Europe'),
    ('Europe/Athens',          'EET',   '2 hours',     TRUE,  'Europe'),
    ('Europe/Bucharest',       'EET',   '2 hours',     TRUE,  'Europe'),
    ('Europe/Kiev',            'EET',   '2 hours',     TRUE,  'Europe'),
    ('Europe/Moscow',          'MSK',   '3 hours',     FALSE, 'Europe'),
    ('Asia/Dubai',             'GST',   '4 hours',     FALSE, 'Asia'),
    ('Asia/Karachi',           'PKT',   '5 hours',     FALSE, 'Asia'),
    ('Asia/Kolkata',           'IST',   '5 hours 30 minutes', FALSE, 'Asia'),
    ('Asia/Dhaka',             'BST',   '6 hours',     FALSE, 'Asia'),
    ('Asia/Bangkok',           'ICT',   '7 hours',     FALSE, 'Asia'),
    ('Asia/Singapore',         'SGT',   '8 hours',     FALSE, 'Asia'),
    ('Asia/Hong_Kong',         'HKT',   '8 hours',     FALSE, 'Asia'),
    ('Asia/Shanghai',          'CST',   '8 hours',     FALSE, 'Asia'),
    ('Asia/Taipei',            'CST',   '8 hours',     FALSE, 'Asia'),
    ('Asia/Seoul',             'KST',   '9 hours',     FALSE, 'Asia'),
    ('Asia/Tokyo',             'JST',   '9 hours',     FALSE, 'Asia'),
    ('Australia/Perth',        'AWST',  '8 hours',     FALSE, 'Oceania'),
    ('Australia/Adelaide',     'ACST',  '9 hours 30 minutes', TRUE, 'Oceania'),
    ('Australia/Sydney',       'AEST',  '10 hours',    TRUE,  'Oceania'),
    ('Pacific/Auckland',       'NZST',  '12 hours',    TRUE,  'Pacific'),
    ('Africa/Cairo',           'EET',   '2 hours',     FALSE, 'Africa'),
    ('Africa/Johannesburg',    'SAST',  '2 hours',     FALSE, 'Africa'),
    ('Africa/Lagos',           'WAT',   '1 hour',      FALSE, 'Africa'),
    ('Africa/Nairobi',         'EAT',   '3 hours',     FALSE, 'Africa')
ON CONFLICT (name) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 3. Global OAuth Scopes (tenant_id NULL = global)
-- ────────────────────────────────────────────────────────────
-- We use a placeholder tenant that does NOT exist so ON CONFLICT
-- is safe; applications will create their own per-tenant scopes.
-- Global scopes reference a well-known nil UUID for tenant_id.
-- In production, insert per-tenant scopes via the app layer.

-- Standard OpenID Connect / OAuth 2.0 scopes (global templates)
-- Note: tenant_id is NOT NULL in the schema, so we use a temporary
-- variable referencing the first created tenant. Applications
-- should seed these per tenant. Below we show the pattern.
-- Since we cannot reference a tenant that doesn't exist yet,
-- we document the typical scope set. The application layer should
-- call this after creating the first tenant.

DO $$
DECLARE
    v_first_tenant UUID;
BEGIN
    -- Only seed if at least one tenant exists
    SELECT id INTO v_first_tenant FROM tenants LIMIT 1;

    IF v_first_tenant IS NOT NULL THEN
        INSERT INTO oauth_scopes (tenant_id, name, description, is_default, is_public) VALUES
            (v_first_tenant, 'openid',         'OpenID Connect: request the use of the OpenID Connect protocol',           TRUE,  TRUE),
            (v_first_tenant, 'profile',         'Access basic profile information (name, picture, website)',                TRUE,  TRUE),
            (v_first_tenant, 'email',           'Access the user''s email address',                                        TRUE,  TRUE),
            (v_first_tenant, 'phone',           'Access the user''s phone number',                                         FALSE, TRUE),
            (v_first_tenant, 'address',         'Access the user''s physical address',                                     FALSE, TRUE),
            (v_first_tenant, 'offline_access',  'Issue a refresh token for long-lived access',                             FALSE, TRUE),
            (v_first_tenant, 'read',            'Read-only access to resources',                                           FALSE, TRUE),
            (v_first_tenant, 'write',           'Write access to resources',                                               FALSE, FALSE),
            (v_first_tenant, 'admin',           'Administrative access',                                                   FALSE, FALSE),
            (v_first_tenant, 'mfa',             'Confirm or manage MFA settings',                                          FALSE, FALSE)
        ON CONFLICT (tenant_id, name) DO NOTHING;
    END IF;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 4. Sample Identity Provider templates
--    (status = 'inactive' so they require configuration before use)
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_first_tenant UUID;
BEGIN
    SELECT id INTO v_first_tenant FROM tenants LIMIT 1;

    IF v_first_tenant IS NOT NULL THEN
        INSERT INTO identity_providers
            (tenant_id, name, slug, provider_type, status,
             authorization_endpoint, token_endpoint, userinfo_endpoint,
             jwks_uri, logo_url, button_label, auto_provision, config)
        VALUES
        -- Google
        (v_first_tenant,
         'Google', 'google', 'google', 'inactive',
         'https://accounts.google.com/o/oauth2/v2/auth',
         'https://oauth2.googleapis.com/token',
         'https://www.googleapis.com/oauth2/v3/userinfo',
         'https://www.googleapis.com/oauth2/v3/certs',
         'https://www.gstatic.com/images/branding/product/1x/gsa_512dp.png',
         'Continue with Google',
         TRUE,
         '{"scopes": ["openid", "profile", "email"]}'::jsonb),

        -- GitHub
        (v_first_tenant,
         'GitHub', 'github', 'github', 'inactive',
         'https://github.com/login/oauth/authorize',
         'https://github.com/login/oauth/access_token',
         'https://api.github.com/user',
         NULL,
         'https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png',
         'Continue with GitHub',
         TRUE,
         '{"scopes": ["read:user", "user:email"]}'::jsonb),

        -- Microsoft
        (v_first_tenant,
         'Microsoft', 'microsoft', 'microsoft', 'inactive',
         'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
         'https://login.microsoftonline.com/common/oauth2/v2.0/token',
         'https://graph.microsoft.com/oidc/userinfo',
         'https://login.microsoftonline.com/common/discovery/v2.0/keys',
         'https://learn.microsoft.com/en-us/azure/active-directory/develop/media/howto-add-branding-in-azure-ad-apps/ms-symbollockup_mssymbol_19.svg',
         'Continue with Microsoft',
         TRUE,
         '{"scopes": ["openid", "profile", "email", "User.Read"]}'::jsonb),

        -- Auth0
        (v_first_tenant,
         'Auth0', 'auth0', 'auth0', 'inactive',
         'https://{your-domain}.auth0.com/authorize',
         'https://{your-domain}.auth0.com/oauth/token',
         'https://{your-domain}.auth0.com/userinfo',
         'https://{your-domain}.auth0.com/.well-known/jwks.json',
         NULL,
         'Continue with Auth0',
         TRUE,
         '{"scopes": ["openid", "profile", "email"]}'::jsonb),

        -- Okta
        (v_first_tenant,
         'Okta', 'okta', 'okta', 'inactive',
         'https://{your-domain}.okta.com/oauth2/v1/authorize',
         'https://{your-domain}.okta.com/oauth2/v1/token',
         'https://{your-domain}.okta.com/oauth2/v1/userinfo',
         'https://{your-domain}.okta.com/oauth2/v1/keys',
         NULL,
         'Continue with Okta',
         TRUE,
         '{"scopes": ["openid", "profile", "email"]}'::jsonb)

        ON CONFLICT (tenant_id, slug) DO NOTHING;
    END IF;
END;
$$;

-- ────────────────────────────────────────────────────────────
-- 5. PII Data Classification registry (global – tenant_id NULL)
--    Documents which columns hold PII and under which regulations.
-- ────────────────────────────────────────────────────────────
INSERT INTO pii_data_classifications
    (tenant_id, table_name, column_name, classification, regulations, is_encrypted, notes)
VALUES
    -- users
    (NULL, 'users', 'email_encrypted',    'sensitive_pii', ARRAY['gdpr','ccpa','pipeda']::pii_regulation[], TRUE,  'Email address – encrypted with AES-256'),
    (NULL, 'users', 'email_hash',         'internal',      ARRAY['gdpr','ccpa']::pii_regulation[],          FALSE, 'SHA-256 of email for lookup; cannot reconstruct PII'),
    (NULL, 'users', 'phone_encrypted',    'sensitive_pii', ARRAY['gdpr','ccpa']::pii_regulation[],          TRUE,  'Phone number – encrypted'),
    (NULL, 'users', 'phone_hash',         'internal',      ARRAY['gdpr','ccpa']::pii_regulation[],          FALSE, 'SHA-256 of phone for lookup'),
    (NULL, 'users', 'last_login_ip',      'confidential',  ARRAY['gdpr','ccpa']::pii_regulation[],          FALSE, 'IP address may be PII under GDPR'),
    -- user_profiles
    (NULL, 'user_profiles', 'first_name_encrypted', 'sensitive_pii', ARRAY['gdpr','ccpa']::pii_regulation[], TRUE, 'First name – encrypted'),
    (NULL, 'user_profiles', 'last_name_encrypted',  'sensitive_pii', ARRAY['gdpr','ccpa']::pii_regulation[], TRUE, 'Last name – encrypted'),
    (NULL, 'user_profiles', 'address_encrypted',    'sensitive_pii', ARRAY['gdpr','ccpa','hipaa']::pii_regulation[], TRUE, 'Full address – encrypted'),
    (NULL, 'user_profiles', 'birth_year',            'confidential',  ARRAY['gdpr','ccpa','coppa']::pii_regulation[], FALSE, 'Birth year (not full DOB)'),
    -- mfa_devices
    (NULL, 'mfa_devices', 'totp_secret_encrypted',  'restricted',    ARRAY['gdpr']::pii_regulation[], TRUE, 'TOTP secret – AES-256 encrypted'),
    (NULL, 'mfa_devices', 'destination_encrypted',  'sensitive_pii', ARRAY['gdpr','ccpa']::pii_regulation[], TRUE, 'SMS/Email destination – encrypted'),
    (NULL, 'mfa_devices', 'push_token_encrypted',   'restricted',    ARRAY['gdpr']::pii_regulation[], TRUE, 'Push notification token – encrypted'),
    -- identity_providers
    (NULL, 'identity_providers', 'client_secret_encrypted', 'restricted', '{}', TRUE, 'OAuth client secret – AES-256 encrypted'),
    -- federated_identities
    (NULL, 'federated_identities', 'access_token_encrypted',  'restricted', ARRAY['gdpr']::pii_regulation[], TRUE, 'IdP access token – encrypted'),
    (NULL, 'federated_identities', 'refresh_token_encrypted', 'restricted', ARRAY['gdpr']::pii_regulation[], TRUE, 'IdP refresh token – encrypted'),
    -- saml_configurations
    (NULL, 'saml_configurations', 'sp_private_key_encrypted', 'restricted', '{}', TRUE, 'SAML SP private key – AES-256 encrypted'),
    -- oidc_configurations
    (NULL, 'oidc_configurations', 'client_secret_encrypted', 'restricted', '{}', TRUE, 'OIDC client secret – AES-256 encrypted')
ON CONFLICT (tenant_id, table_name, column_name) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 6. Sample UI translations (common auth strings)
-- ────────────────────────────────────────────────────────────
INSERT INTO ui_translations (tenant_id, language_code, namespace, key, value) VALUES
    -- English
    (NULL, 'en', 'auth', 'login.title',                   'Sign In'),
    (NULL, 'en', 'auth', 'login.email_placeholder',       'Email address'),
    (NULL, 'en', 'auth', 'login.password_placeholder',    'Password'),
    (NULL, 'en', 'auth', 'login.submit',                  'Sign In'),
    (NULL, 'en', 'auth', 'login.forgot_password',         'Forgot your password?'),
    (NULL, 'en', 'auth', 'login.no_account',              'Don''t have an account?'),
    (NULL, 'en', 'auth', 'login.register_link',           'Create one'),
    (NULL, 'en', 'auth', 'mfa.title',                     'Two-Factor Authentication'),
    (NULL, 'en', 'auth', 'mfa.enter_code',                'Enter the code from your authenticator app'),
    (NULL, 'en', 'auth', 'mfa.use_recovery',              'Use a recovery code'),
    (NULL, 'en', 'auth', 'errors.invalid_credentials',    'Invalid email or password'),
    (NULL, 'en', 'auth', 'errors.account_locked',         'Account is temporarily locked. Please try again later.'),
    (NULL, 'en', 'auth', 'errors.mfa_required',           'Multi-factor authentication is required'),
    -- French
    (NULL, 'fr', 'auth', 'login.title',                   'Se connecter'),
    (NULL, 'fr', 'auth', 'login.email_placeholder',       'Adresse e-mail'),
    (NULL, 'fr', 'auth', 'login.password_placeholder',    'Mot de passe'),
    (NULL, 'fr', 'auth', 'login.submit',                  'Se connecter'),
    (NULL, 'fr', 'auth', 'login.forgot_password',         'Mot de passe oublié ?'),
    (NULL, 'fr', 'auth', 'mfa.title',                     'Authentification à deux facteurs'),
    (NULL, 'fr', 'auth', 'errors.invalid_credentials',    'E-mail ou mot de passe incorrect'),
    -- German
    (NULL, 'de', 'auth', 'login.title',                   'Anmelden'),
    (NULL, 'de', 'auth', 'login.email_placeholder',       'E-Mail-Adresse'),
    (NULL, 'de', 'auth', 'login.password_placeholder',    'Passwort'),
    (NULL, 'de', 'auth', 'login.submit',                  'Anmelden'),
    (NULL, 'de', 'auth', 'login.forgot_password',         'Passwort vergessen?'),
    (NULL, 'de', 'auth', 'mfa.title',                     'Zwei-Faktor-Authentifizierung'),
    (NULL, 'de', 'auth', 'errors.invalid_credentials',    'Ungültige E-Mail oder Passwort'),
    -- Spanish
    (NULL, 'es', 'auth', 'login.title',                   'Iniciar sesión'),
    (NULL, 'es', 'auth', 'login.email_placeholder',       'Correo electrónico'),
    (NULL, 'es', 'auth', 'login.password_placeholder',    'Contraseña'),
    (NULL, 'es', 'auth', 'login.submit',                  'Iniciar sesión'),
    (NULL, 'es', 'auth', 'login.forgot_password',         '¿Olvidaste tu contraseña?'),
    (NULL, 'es', 'auth', 'mfa.title',                     'Autenticación de dos factores'),
    (NULL, 'es', 'auth', 'errors.invalid_credentials',    'Correo electrónico o contraseña no válidos'),
    -- Japanese
    (NULL, 'ja', 'auth', 'login.title',                   'ログイン'),
    (NULL, 'ja', 'auth', 'login.email_placeholder',       'メールアドレス'),
    (NULL, 'ja', 'auth', 'login.password_placeholder',    'パスワード'),
    (NULL, 'ja', 'auth', 'login.submit',                  'ログイン'),
    (NULL, 'ja', 'auth', 'errors.invalid_credentials',    'メールアドレスまたはパスワードが正しくありません'),
    -- Portuguese (Brazil)
    (NULL, 'pt-BR', 'auth', 'login.title',                'Entrar'),
    (NULL, 'pt-BR', 'auth', 'login.email_placeholder',    'Endereço de e-mail'),
    (NULL, 'pt-BR', 'auth', 'login.password_placeholder', 'Senha'),
    (NULL, 'pt-BR', 'auth', 'login.submit',               'Entrar'),
    (NULL, 'pt-BR', 'auth', 'errors.invalid_credentials', 'E-mail ou senha inválidos')
ON CONFLICT (tenant_id, language_code, namespace, key) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 7. Sample rate-limit configuration
--    Applied to the first tenant if one exists.
-- ────────────────────────────────────────────────────────────
DO $$
DECLARE
    v_first_tenant UUID;
BEGIN
    SELECT id INTO v_first_tenant FROM tenants LIMIT 1;

    IF v_first_tenant IS NOT NULL THEN
        INSERT INTO rate_limit_configs (tenant_id, resource, max_requests, window_sec, scope, action) VALUES
            (v_first_tenant, 'login',                   5,   60,   'ip',     'block'),
            (v_first_tenant, 'login',                   10,  60,   'user',   'block'),
            (v_first_tenant, 'password_reset',          3,   3600, 'ip',     'block'),
            (v_first_tenant, 'mfa_verify',              5,   300,  'user',   'block'),
            (v_first_tenant, 'email_verification',      5,   3600, 'user',   'block'),
            (v_first_tenant, 'oauth_authorize',         30,  60,   'ip',     'captcha'),
            (v_first_tenant, 'token_refresh',           60,  60,   'user',   'delay'),
            (v_first_tenant, 'api',                     1000, 60,  'app',    'block'),
            (v_first_tenant, 'registration',            10,  3600, 'ip',     'captcha')
        ON CONFLICT (tenant_id, resource, scope) DO NOTHING;
    END IF;
END;
$$;
