# Multi-Tenant Authentication Framework – PostgreSQL Database Design

A production-ready, comprehensive PostgreSQL database schema for a multi-tenant authentication framework. Covers MFA, OAuth 2.0, SSO (SAML 2.0 & OIDC), external identity providers, localised login, GDPR compliance, PII handling, and US/EU regulations.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [File Structure](#file-structure)
3. [Quick Start](#quick-start)
4. [Schema Areas](#schema-areas)
   - [Tenants & Organizations](#tenants--organizations)
   - [Users & Authentication](#users--authentication)
   - [MFA](#mfa)
   - [OAuth 2.0](#oauth-20)
   - [SSO & Identity Providers](#sso--identity-providers)
   - [Federated Identities](#federated-identities)
   - [Localization](#localization)
   - [Audit & Compliance](#audit--compliance)
   - [Security](#security)
   - [PII & Data Classification](#pii--data-classification)
5. [Key Design Decisions](#key-design-decisions)
6. [Security Model](#security-model)
7. [Compliance](#compliance)
8. [Performance](#performance)
9. [Maintenance](#maintenance)
10. [Environment Setup](#environment-setup)

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                   │
│                                                          │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │  Tenants   │  │ Applications │  │  Organizations  │  │
│  └────────────┘  └──────────────┘  └─────────────────┘  │
│         │               │                  │             │
│  ┌──────▼───────────────▼──────────────────▼──────────┐  │
│  │                    Users                           │  │
│  │          (encrypted PII, UUID v7 IDs)             │  │
│  └─────┬──────────┬──────────┬──────────┬────────────┘  │
│        │          │          │          │               │
│  ┌─────▼──┐  ┌────▼───┐  ┌──▼─────┐  ┌─▼──────────┐   │
│  │ Sessions│  │  MFA   │  │ OAuth  │  │    SSO     │   │
│  └─────────┘  └────────┘  └────────┘  └────────────┘   │
│                                                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────┐  │
│  │  Audit Logs │  │ Compliance   │  │  Localization  │  │
│  │  (RLS, BRIN)│  │(GDPR/CCPA)   │  │(i18n,tz,region)│  │
│  └─────────────┘  └──────────────┘  └────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

### Core Principles

| Principle | Implementation |
|-----------|---------------|
| Multi-tenancy | Every table carries `tenant_id`; RLS enforces boundaries |
| PII Protection | Sensitive fields encrypted with AES-256 (pgcrypto); SHA-256 hash for lookup |
| UUID v7 | All primary keys use sortable, timestamp-prefixed UUIDs |
| Immutable Audit | `audit_logs` has `NO UPDATE/DELETE` RLS policies; tamper-evident chain |
| Least Privilege | RLS + application-level `SET app.current_tenant_id` per connection |
| Compliance | GDPR (right-to-erasure, consent, retention), CCPA, HIPAA-ready |

---

## File Structure

```
auth-framework-db/
├── enums.sql                      # All ENUM type definitions
├── schema.sql                     # Tables, constraints, foreign keys
├── functions.sql                  # PL/pgSQL utility functions
├── rls_policies.sql               # Row-Level Security policies
├── triggers.sql                   # Automated triggers
├── indexes.sql                    # Performance indexes
├── views.sql                      # Common query views
├── seed_data.sql                  # Reference data (languages, timezones, IdP templates)
├── migrations/
│   └── 001_initial_schema.sql    # Self-contained migration (apply to fresh DB)
└── README.md                      # This document
```

---

## Quick Start

### Option A – Apply individual files (development)

```bash
# 1. Create a database
createdb auth_framework

# 2. Apply in dependency order
psql -d auth_framework -f enums.sql
psql -d auth_framework -f schema.sql
psql -d auth_framework -f functions.sql
psql -d auth_framework -f rls_policies.sql
psql -d auth_framework -f triggers.sql
psql -d auth_framework -f indexes.sql
psql -d auth_framework -f views.sql
psql -d auth_framework -f seed_data.sql
```

### Option B – Single migration file (CI / production)

```bash
createdb auth_framework
psql -d auth_framework -v ON_ERROR_STOP=1 -f migrations/001_initial_schema.sql
```

### Minimum PostgreSQL version

PostgreSQL **14** or later (required for `pg_trgm`, `btree_gin`, and modern JSONB operators).

---

## Schema Areas

### Tenants & Organizations

| Table | Purpose |
|-------|---------|
| `tenants` | Top-level tenant with plan, data residency, MFA policy |
| `tenant_settings` | Per-tenant security & compliance configuration |
| `organizations` | Hierarchical org units within a tenant |
| `applications` | OAuth client apps registered to a tenant |

Each tenant has a URL-safe `slug`, data residency region (`us`, `eu`, `uk`, `ca`, `au`, `ap`, `global`), and configurable limits for users and applications.

**Tenant isolation** is enforced at the database layer via Row-Level Security (see [Security Model](#security-model)).

---

### Users & Authentication

| Table | Purpose |
|-------|---------|
| `users` | Core user record; encrypted email/phone; login tracking |
| `user_profiles` | Extended profile (encrypted name/address, locale, avatar) |
| `user_credentials` | Passwords (bcrypt), passkeys (WebAuthn), magic links |
| `user_roles` | User ↔ Role assignments (optionally scoped to an application) |
| `roles` | Tenant-defined roles; system roles cannot be deleted |
| `permissions` | Resource × action permission definitions |
| `role_permissions` | Many-to-many role ↔ permission mapping |
| `user_sessions` | Active sessions with expiry, IP, device fingerprint |
| `password_reset_tokens` | Time-limited, single-use reset tokens |
| `email_verification_tokens` | Email address verification tokens |

**Password hashing** uses `crypt()` with the `bf` (blowfish/bcrypt) algorithm via pgcrypto. The application layer should use argon2id via a language SDK; bcrypt is used here as the PostgreSQL-native fallback.

---

### MFA

| Table | Purpose |
|-------|---------|
| `mfa_devices` | Enrolled MFA devices (TOTP, SMS, Email, WebAuthn, Push) |
| `mfa_recovery_codes` | Backup recovery codes (bcrypt-hashed) |
| `mfa_challenges` | In-flight MFA challenge/response state |

**Supported methods:**

| Method | Storage |
|--------|---------|
| TOTP | Encrypted secret, issuer, algorithm, digits, period |
| SMS | Encrypted phone destination |
| Email | Encrypted email destination |
| WebAuthn | COSE public key, credential ID, AAGUID, sign counter, RP ID |
| Push | Encrypted push token, provider (FCM/APNs) |
| Backup Code | bcrypt hash of 10-character hex codes |

---

### OAuth 2.0

| Table | Purpose |
|-------|---------|
| `oauth_scopes` | Available scopes per tenant |
| `oauth_application_scopes` | Scopes registered to an application |
| `oauth_authorization_codes` | Short-lived codes (PKCE: S256/plain) |
| `oauth_tokens` | Access, refresh, and ID tokens |

**Supported grant types:** `authorization_code`, `client_credentials`, `refresh_token`, `device_code`.

**PKCE** is required by default (`require_pkce = TRUE` on applications). The `code_challenge_method` column accepts `S256` or `plain`.

Token storage follows the **hash-then-store** pattern: only SHA-256 hashes of tokens are stored in the database. Raw tokens are returned to the application once and never persisted.

---

### SSO & Identity Providers

| Table | Purpose |
|-------|---------|
| `identity_providers` | Generic IdP configuration (OIDC, SAML, OAuth2, social) |
| `saml_configurations` | SAML 2.0 SP metadata, signing/encryption keys |
| `oidc_configurations` | OIDC discovery, client credentials, PKCE, claims mapping |
| `sso_sessions` | Cross-application SSO session federation |

**Pre-built IdP templates** (seeded as inactive): Google, GitHub, Microsoft, Auth0, Okta.

**SAML 2.0 features:**
- SP-initiated and IdP-initiated flows
- Signed requests and assertions (RSA-SHA256)
- Encrypted assertions support
- Configurable NameID format
- Attribute mapping via JSONB

**OIDC features:**
- Discovery URL support
- RS256 / ES256 ID token signing
- PKCE support
- Custom claims mapping

---

### Federated Identities

| Table | Purpose |
|-------|---------|
| `federated_identities` | Links a local user to an external IdP subject |
| `linked_accounts` | Cross-provider or delegated account linking |

The `subject` field stores the IdP-assigned user identifier. Access and refresh tokens from the IdP are stored encrypted.

---

### Localization

| Table | Purpose |
|-------|---------|
| `languages` | BCP-47 language codes, native names, RTL flag |
| `timezones` | IANA timezone registry with UTC offsets |
| `user_localization_preferences` | Per-user language, timezone, date/time/number formats |
| `tenant_regional_settings` | Regional compliance settings per tenant |
| `ui_translations` | Multi-language UI strings (keyed by namespace + key) |

**39 languages** and **49 timezones** are seeded by default.

**Tenant regional settings** allow per-region configuration of GDPR, CCPA, eIDAS compliance, data residency restrictions, and cross-border transfer rules.

---

### Audit & Compliance

| Table | Purpose |
|-------|---------|
| `audit_logs` | Immutable, tamper-evident audit trail |
| `user_consents` | GDPR/CCPA consent tracking per consent type |
| `data_retention_policies` | Configurable retention rules per table |
| `pii_deletion_requests` | Right-to-erasure (GDPR Art. 17) requests |

**Audit log** features:
- 42 distinct event types covering authentication, MFA, OAuth, SSO, account lifecycle, and compliance events
- `previous_log_id` chain for tamper detection
- RLS prevents UPDATE and DELETE by non-service roles
- BRIN index for efficient time-range queries

**GDPR workflow:**
1. User submits deletion request → `pii_deletion_requests` row created
2. Trigger sets `deadline_at = requested_at + 30 days`
3. `v_pending_deletion_requests` view shows urgency status
4. `anonymise_user()` function executes the erasure

---

### Security

| Table | Purpose |
|-------|---------|
| `device_fingerprints` | Device trust tracking (unknown → unverified → verified → managed) |
| `security_events` | Risk events (brute force, impossible travel, credential stuffing, etc.) |
| `rate_limit_configs` | Per-resource rate limit rules |
| `ip_allowlists` | IP allowlists and blocklists (CIDR notation) |
| `api_keys` | Long-lived API keys with scope restrictions |

---

### PII & Data Classification

| Table | Purpose |
|-------|---------|
| `pii_data_classifications` | Registry of PII fields, their classification level, and applicable regulations |

**Classification levels:** `public`, `internal`, `confidential`, `restricted`, `sensitive_pii`, `financial`, `health`

**Tracked regulations:** GDPR, CCPA, HIPAA, COPPA, PIPEDA, LGPD, PDPA, eIDAS, FERPA, GLBA

---

## Key Design Decisions

### UUID v7

All primary keys use UUID v7 generated by the `generate_uuid_v7()` function. UUID v7 provides:
- **Sortability** – timestamp prefix allows B-tree index locality
- **Uniqueness** – 74 bits of randomness
- **Discoverability** – timestamp extraction for debugging

```sql
SELECT generate_uuid_v7();
-- → 018f6b2a-3d01-7abc-8def-0123456789ab
--   ^^^^^^^^^^ 48-bit unix milliseconds
```

### Encrypted PII

Fields classified as `sensitive_pii` or `restricted` are stored as `BYTEA` using `pgp_sym_encrypt` (AES-256-CBC via pgcrypto). The encryption key is supplied by the application; never stored in the database.

```sql
-- Write
UPDATE users SET email_encrypted = encrypt_pii('user@example.com', $app_key);

-- Read
SELECT decrypt_pii(email_encrypted, $app_key) AS email FROM users WHERE id = $id;
```

A SHA-256 hash of the plaintext is stored alongside for indexed lookup without decryption.

### Hash-then-store tokens

Tokens (session tokens, OAuth tokens, password reset tokens) are **never stored in plaintext**. The raw token is returned to the application once; only `SHA-256(token)` is stored.

```sql
-- Application stores hash, returns raw token to client
SELECT sha256_hex('raw-secret-token');
```

---

## Security Model

### Row-Level Security (RLS)

Every table has RLS enabled. The application must set session-level variables before executing queries:

```sql
-- At connection start / after authentication
SET app.current_tenant_id = '018f6b2a-...';   -- UUID of authenticated tenant
SET app.current_user_id   = '018f6c1b-...';   -- UUID of authenticated user
SET app.is_service_role   = 'false';            -- 'true' for internal services
```

**Policy hierarchy:**
1. Service role (`is_service_role = 'true'`) → full access
2. Tenant isolation → restrict to `tenant_id = current_tenant_id()`
3. Self-read policies → users may read their own rows

### Audit log immutability

```sql
-- These policies prevent tampering:
CREATE POLICY audit_logs_no_update ON audit_logs FOR UPDATE USING (is_service_role());
CREATE POLICY audit_logs_no_delete ON audit_logs FOR DELETE USING (is_service_role());
```

### Password security

- Stored with `bcrypt` (cost factor 12) via pgcrypto's `crypt()`
- Password history enforced by trigger (last 10 hashes)
- Account lockout after configurable failed attempts
- Auto-unlock when `locked_until` timestamp passes

---

## Compliance

### GDPR (EU)

| Requirement | Implementation |
|-------------|---------------|
| Right to erasure (Art. 17) | `anonymise_user()` function; `pii_deletion_requests` table |
| Right to access (Art. 15) | `pii_deletion_requests` with `request_type = 'access'` |
| Data portability (Art. 20) | `pii_deletion_requests` with `request_type = 'portability'` |
| Consent (Art. 7) | `user_consents` with 10 consent types, versioned documents |
| Data minimisation | Birth year only (not full DOB); coarse geolocation |
| Retention | `data_retention_policies` per table; automated cleanup |
| Audit trail | Immutable `audit_logs` with actor, IP, outcome |
| Data residency | `data_residency_region` on tenants; `tenant_regional_settings` |

### CCPA (California)

| Requirement | Implementation |
|-------------|---------------|
| Right to know | Audit logs; data classification registry |
| Right to delete | `pii_deletion_requests`; `anonymise_user()` |
| Right to opt-out | `user_consents` with `data_sharing`, `marketing_emails` types |
| Non-discrimination | Enforced at application layer |

### eIDAS (EU)

- `eidas_enabled` flag in `tenant_regional_settings`
- Identity assurance level can be stored in `federated_identities.idp_profile`
- SAML 2.0 support for qualified electronic signatures

### US Regulations

| Regulation | Notes |
|------------|-------|
| HIPAA | `health` classification in `pii_data_classifications`; encryption at rest |
| COPPA | `birth_year` only stored; `coppa` in regulation enums |
| FERPA | `ferpa` in regulation enums; student record protection |
| GLBA | `financial` classification; encryption enforced |

---

## Performance

### Index strategy

| Pattern | Index type |
|---------|-----------|
| Tenant + column lookups | B-tree composite (tenant_id, column) |
| Active records | Partial B-tree `WHERE status = 'active'` |
| Token hash lookups | UNIQUE B-tree |
| Time-series audit logs | BRIN (append-only, temporal) |
| Translation key search | GIN + trigram (`gin_trgm_ops`) |
| Session / token expiry scans | Partial index on `expires_at WHERE status = 'active'` |

### Views

| View | Purpose |
|------|---------|
| `v_active_users` | Active users with tenant context (no PII) |
| `v_user_mfa_status` | MFA enrollment summary per user |
| `v_active_sessions` | Active sessions with device and app context |
| `v_oauth_token_status` | Token overview with effective expiry flag |
| `v_user_consents` | Consent status with active/inactive classification |
| `v_tenant_security_overview` | Aggregated security metrics per tenant |
| `v_idp_federation_summary` | IdP config with linked identity counts |
| `v_pending_deletion_requests` | GDPR deletion requests with urgency |
| `v_audit_recent_failures` | Recent auth failures (SIEM integration) |
| `v_application_oauth_summary` | OAuth usage per application |

---

## Maintenance

### Token / session cleanup

Run periodically (e.g., every 15 minutes via `pg_cron`):

```sql
SELECT cleanup_expired_tokens();
```

This marks expired `oauth_tokens` and `user_sessions` as expired, and hard-deletes stale MFA challenges and password reset tokens.

### Data retention

Run nightly:

```sql
SELECT run_data_retention('018f6b2a-...', 'audit_logs');
SELECT run_data_retention('018f6b2a-...', 'user_sessions');
-- repeat for each table + tenant combination
```

### PII deletion processing

```sql
-- Process a deletion request
SELECT anonymise_user(
    '018f6c1b-...',   -- user_id
    '018f6b2a-...'    -- tenant_id
);

-- Update request status
UPDATE pii_deletion_requests
SET status       = 'completed',
    completed_at = now()
WHERE id = '018f6d2c-...';
```

---

## Environment Setup

### Required extensions

```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- AES-256 encryption, bcrypt
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- Trigram text search
CREATE EXTENSION IF NOT EXISTS "btree_gin";  -- GIN indexes on scalar types
CREATE EXTENSION IF NOT EXISTS "unaccent";   -- Locale-insensitive search
```

### Application connection setup

```sql
-- Set at the start of each application connection:
SET app.current_tenant_id = '<tenant-uuid>';
SET app.current_user_id   = '<user-uuid>';
SET app.is_service_role   = 'false';

-- For internal services / migrations:
SET app.is_service_role = 'true';
```

### Encryption key management

The `encrypt_pii()` and `decrypt_pii()` functions accept the encryption key as a parameter. In production:

1. Use a dedicated KMS (AWS KMS, GCP Cloud KMS, HashiCorp Vault)
2. Pass the data encryption key (DEK) into the function at query time
3. Rotate keys by re-encrypting affected columns and updating `pii_data_classifications.encryption_key_id`
4. Never store the encryption key in the database or in `schema.sql`

---

---

## .NET Core API Implementation

A full .NET 9 REST API implementation is provided in the `auth-framework-api/` directory.

### Project Structure

```
auth-framework-api/
├── src/
│   ├── AuthFramework.Api/           # ASP.NET Core Web API (controllers, middleware, Program.cs)
│   ├── AuthFramework.Core/          # Domain entities, enums, models, constants
│   ├── AuthFramework.Application/   # Services, interfaces, DTOs
│   ├── AuthFramework.Infrastructure/# EF Core DbContext, repositories, DI setup
│   └── AuthFramework.Shared/        # Utilities (UUID v7, TOTP, bcrypt), exceptions, extensions
├── tests/
│   ├── AuthFramework.Tests.Unit/    # xUnit unit tests (30 tests)
│   └── AuthFramework.Tests.Integration/ # Testcontainers integration tests
└── AuthFramework.sln
```

### Quick Start

```bash
# 1. Start PostgreSQL and the API via Docker Compose
docker compose up -d

# 2. Or run locally (requires PostgreSQL)
cd auth-framework-api
dotnet restore
dotnet run --project src/AuthFramework.Api
# API available at http://localhost:5000
# Swagger UI at http://localhost:5000/swagger
```

### Running Tests

```bash
cd auth-framework-api
dotnet test tests/AuthFramework.Tests.Unit
```

### API Documentation

| Resource | Location |
|---|---|
| OpenAPI 3.1 spec | `docs/openapi.json` |
| API reference | `docs/API.md` |
| Implementation guide | `docs/IMPLEMENTATION.md` |
| Security guide | `docs/SECURITY.md` |
| GDPR compliance | `docs/GDPR.md` |
| Postman collection | `samples/postman-collection.json` |
| cURL examples | `samples/curl-examples.sh` |
| C# examples | `samples/csharp-examples.cs` |

### Key API Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/register` | User registration |
| POST | `/api/auth/login` | Login (returns JWT + optional MFA challenge) |
| POST | `/api/auth/refresh-token` | Refresh access token |
| POST | `/api/mfa/enroll` | Enroll MFA device (TOTP, SMS, Email) |
| POST | `/api/mfa/verify` | Verify MFA challenge |
| GET | `/api/oauth/authorize` | OAuth 2.0 authorization code flow |
| POST | `/api/oauth/token` | OAuth 2.0 token endpoint |
| GET | `/api/sso/providers` | List SSO providers |
| GET | `/api/users/me` | Get current user profile |
| GET | `/api/users/me/data-export` | GDPR data export |
| GET | `/api/admin/audit-logs` | Admin audit log query |

---

## License

This schema is released under the MIT License. See repository root for details.
