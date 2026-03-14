-- ============================================================
-- Auth Framework - Azure PostgreSQL Initialization Script
-- ============================================================
-- Run as PostgreSQL administrator after server creation.

-- Create application role if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authframework_app') THEN
        CREATE ROLE authframework_app WITH LOGIN;
        RAISE NOTICE 'Role authframework_app created';
    ELSE
        RAISE NOTICE 'Role authframework_app already exists';
    END IF;
END
$$;

-- Grant database connection
GRANT CONNECT ON DATABASE authframework TO authframework_app;

-- Grant schema usage
GRANT USAGE ON SCHEMA public TO authframework_app;

-- Grant table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authframework_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authframework_app;

-- Grant sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authframework_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO authframework_app;

-- Grant function execution
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authframework_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO authframework_app;

-- Enable Row Level Security defaults
ALTER DATABASE authframework SET row_security = on;

-- Set connection limits
ALTER ROLE authframework_app CONNECTION LIMIT 50;

-- Set statement timeout for app role (30 seconds)
ALTER ROLE authframework_app SET statement_timeout = '30s';

-- Set lock timeout
ALTER ROLE authframework_app SET lock_timeout = '10s';

-- Configure search path
ALTER ROLE authframework_app SET search_path = public;

RAISE NOTICE 'Auth Framework Azure initialization complete';
