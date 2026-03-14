-- =============================================================================
-- extensions.sql
-- Enable required PostgreSQL extensions for the multi-tenant auth framework
-- UUID v7 support via pgcrypto (gen_random_uuid) and uuid-ossp
-- =============================================================================

-- Core UUID generation (gen_random_uuid() produces UUIDs compatible with v4;
-- a custom uuid_generate_v7() function is defined in functions.sql for true v7)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Full-text search
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- btree_gist for exclusion constraints
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- pg_stat_statements for query performance monitoring
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
