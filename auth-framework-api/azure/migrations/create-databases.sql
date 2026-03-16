-- ============================================================
-- Auth Framework - Multi-Environment Database Creation Script
-- ============================================================
-- Run as PostgreSQL superuser.
-- Adjust environment names as needed.

-- -------------------------------------------------------
-- Development database
-- -------------------------------------------------------
SELECT 'Creating development database...' AS status;
CREATE DATABASE authframework_dev
    WITH OWNER = psqladmin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

COMMENT ON DATABASE authframework_dev IS 'Auth Framework - Development Environment';

-- -------------------------------------------------------
-- Staging database
-- -------------------------------------------------------
SELECT 'Creating staging database...' AS status;
CREATE DATABASE authframework_staging
    WITH OWNER = psqladmin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

COMMENT ON DATABASE authframework_staging IS 'Auth Framework - Staging Environment';

-- -------------------------------------------------------
-- Production database
-- -------------------------------------------------------
SELECT 'Creating production database...' AS status;
CREATE DATABASE authframework
    WITH OWNER = psqladmin
    ENCODING = 'UTF8'
    LC_COLLATE = 'en_US.utf8'
    LC_CTYPE = 'en_US.utf8'
    TEMPLATE = template0;

COMMENT ON DATABASE authframework IS 'Auth Framework - Production Environment';

-- Create application role
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'authframework_app') THEN
        CREATE ROLE authframework_app WITH LOGIN CONNECTION LIMIT 50;
    END IF;
END
$$;

-- Grant access to all databases
GRANT CONNECT ON DATABASE authframework_dev TO authframework_app;
GRANT CONNECT ON DATABASE authframework_staging TO authframework_app;
GRANT CONNECT ON DATABASE authframework TO authframework_app;

-- List created databases
SELECT datname, pg_encoding_to_char(encoding) AS encoding, datcollate
FROM pg_database
WHERE datname LIKE 'authframework%'
ORDER BY datname;
