-- ============================================================
-- Auth Framework - PostgreSQL Extensions Setup
-- ============================================================
-- Run as superuser/administrator on the authframework database.

\c authframework

-- Core extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";        -- UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";          -- Cryptographic functions
CREATE EXTENSION IF NOT EXISTS "pg_trgm";           -- Trigram similarity for search
CREATE EXTENSION IF NOT EXISTS "btree_gin";         -- GIN index support for btree types

-- Optional: Uncomment if needed
-- CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";  -- Query statistics
-- CREATE EXTENSION IF NOT EXISTS "hstore";              -- Key-value store
-- CREATE EXTENSION IF NOT EXISTS "citext";              -- Case-insensitive text
-- CREATE EXTENSION IF NOT EXISTS "ltree";               -- Hierarchical data
-- CREATE EXTENSION IF NOT EXISTS "intarray";            -- Integer array operations
-- CREATE EXTENSION IF NOT EXISTS "tablefunc";           -- crosstab, etc.

-- Verify extensions
SELECT
    extname AS extension_name,
    extversion AS version,
    nspname AS schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid = e.extnamespace
ORDER BY extname;

RAISE NOTICE 'Auth Framework extensions setup complete';
