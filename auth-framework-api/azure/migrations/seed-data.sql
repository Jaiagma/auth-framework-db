-- ============================================================
-- Auth Framework - Azure Reference Data Seeding Script
-- ============================================================
-- Seeds initial reference data for Azure environments.
-- Safe to run multiple times (uses INSERT ... ON CONFLICT DO NOTHING).

SET search_path = public;

-- -------------------------------------------------------
-- Seed: Application roles / permission scopes
-- -------------------------------------------------------
-- Only run if the 'roles' or equivalent table exists
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'roles'
    ) THEN
        INSERT INTO roles (id, name, description, created_at, updated_at)
        VALUES
            (gen_random_uuid(), 'Admin',       'Full system administrator',      NOW(), NOW()),
            (gen_random_uuid(), 'User',        'Standard authenticated user',    NOW(), NOW()),
            (gen_random_uuid(), 'ReadOnly',    'Read-only access to resources',  NOW(), NOW()),
            (gen_random_uuid(), 'ServiceAccount', 'Machine-to-machine service',  NOW(), NOW())
        ON CONFLICT (name) DO NOTHING;
        RAISE NOTICE 'Roles seeded';
    ELSE
        RAISE NOTICE 'Table "roles" not found; skipping role seed';
    END IF;
END $$;

-- -------------------------------------------------------
-- Seed: System configuration
-- -------------------------------------------------------
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name = 'system_configurations'
    ) THEN
        INSERT INTO system_configurations (key, value, description, environment, created_at)
        VALUES
            ('auth.token.expiry_minutes',        '60',    'JWT token expiry in minutes',          'azure', NOW()),
            ('auth.refresh_token.expiry_days',   '7',     'Refresh token expiry in days',         'azure', NOW()),
            ('auth.password.min_length',         '12',    'Minimum password length',              'azure', NOW()),
            ('auth.password.require_uppercase',  'true',  'Require uppercase in password',        'azure', NOW()),
            ('auth.password.require_digit',      'true',  'Require digit in password',            'azure', NOW()),
            ('auth.password.require_special',    'true',  'Require special char in password',     'azure', NOW()),
            ('auth.lockout.max_attempts',        '5',     'Max failed login attempts',            'azure', NOW()),
            ('auth.lockout.duration_minutes',    '15',    'Account lockout duration in minutes',  'azure', NOW()),
            ('audit.retention_days',             '365',   'Audit log retention in days',          'azure', NOW())
        ON CONFLICT (key) DO NOTHING;
        RAISE NOTICE 'System configurations seeded';
    ELSE
        RAISE NOTICE 'Table "system_configurations" not found; skipping config seed';
    END IF;
END $$;

RAISE NOTICE 'Auth Framework Azure seed data complete';
