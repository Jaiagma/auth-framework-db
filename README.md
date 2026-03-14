# Auth Framework DB

A comprehensive **PostgreSQL** database schema for a **multi-tenant authentication framework** with **UUID v7** primary keys, full OAuth 2.0 / OIDC support, SAML 2.0 SSO, MFA, GDPR compliance, PII encryption, and Row-Level Security.

---

## Table of Contents

1. [Features](#features)
2. [UUID v7 – Why & How](#uuid-v7--why--how)
3. [File Structure](#file-structure)
4. [Schema Overview](#schema-overview)
5. [Getting Started](#getting-started)
6. [Security Architecture](#security-architecture)
7. [Compliance](#compliance)
8. [Localization](#localization)
9. [Performance](#performance)
10. [Configuration Reference](#configuration-reference)

---

## Features

| Category | Details |
|---|---|
| **Multi-Tenancy** | Complete data isolation via tenant_id on every table and RLS policies |
| **UUID v7** | Sortable, timestamp-embedded identifiers on all PKs and FKs |
| **MFA** | TOTP, SMS, Email, WebAuthn/FIDO2, Push, Hardware Key, Recovery Codes |
| **OAuth 2.0** | Authorization Code (+PKCE), Client Credentials, Refresh Token, Device Code |
| **OpenID Connect** | Full OIDC support with id_token, userinfo, jwks |
| **SAML 2.0** | SP-initiated and IdP-initiated SSO, signed & encrypted assertions |
| **External IdPs** | Google, GitHub, Microsoft, Auth0, Okta, Facebook, Apple, custom OIDC/SAML |
| **SSO Sessions** | Cross-application SSO session federation with SLO support |
| **Localization** | 30+ languages, 50+ timezones, RTL support, per-user locale preferences |
| **GDPR** | Consent management, right-to-erasure, data export, retention policies |
| **PII Encryption** | AES-256 encrypted PII columns with per-tenant keys via pgcrypto |
| **US Regulations** | CCPA, HIPAA, PCI-DSS, SOX compliance-ready data classification |
| **EU Regulations** | GDPR, eIDAS, data residency zones |
| **Row-Level Security** | PostgreSQL RLS on every table for tenant isolation |
| **Audit Logging** | Partitioned audit_logs table with 40+ event types |
| **Security Events** | Brute-force detection, anomaly tracking, risk scoring |
| **API Keys** | Scoped API keys with prefix-based lookup |
| **Webhooks** | Event-driven webhooks with delivery tracking |

---

## UUID v7 – Why & How

### Why UUID v7?

| Property | UUID v4 | UUID v7 |
|---|---|---|
| Format | Random (128-bit) | Timestamp (48-bit ms) + random |
| Sortable | ❌ No | ✅ Yes (by insertion time) |
| B-tree locality | Poor | Excellent |
| Page splits | Frequent | Rare |
| Debuggability | Opaque | Timestamp extractable |
| Standard | RFC 4122 | RFC 9562 (2024) |

UUID v7 encodes a **48-bit millisecond Unix timestamp** in the most-significant bits, followed by a version nibble (0x7), and random bytes for uniqueness. This gives:

- **Sequential inserts** → minimal B-tree page splits → better write throughput
- **Time-range queries** on `id` without needing a separate `created_at` index
- **Natural ordering** that matches insertion order

### Implementation

```sql
-- Generate a UUID v7
SELECT uuid_generate_v7();
-- → '018f4d7e-7c00-7e3a-b802-3f1a2c4d5e6f'
--    └────────────┘ ← 48-bit ms timestamp

-- Extract the timestamp back from any UUID v7
SELECT uuid_v7_to_timestamptz('018f4d7e-7c00-7e3a-b802-3f1a2c4d5e6f');
-- → '2024-05-13 12:34:56.789+00'
```

All tables use:
```sql
id UUID PRIMARY KEY DEFAULT uuid_generate_v7()
```

Foreign keys reference the UUID v7 primary key directly:
```sql
tenant_id UUID NOT NULL REFERENCES tenants(id)
```

---

## File Structure

```
auth-framework-db/
├── extensions.sql              # PostgreSQL extension installation
├── enums.sql                   # ENUM type definitions
├── functions.sql               # PL/pgSQL functions (uuid_generate_v7, encryption, etc.)
├── schema.sql                  # Complete table definitions
├── triggers.sql                # Audit, timestamp, and validation triggers
├── indexes.sql                 # Performance indexes
├── views.sql                   # Common query views
├── rls_policies.sql            # Row-Level Security policies
├── seed_data.sql               # Reference data (languages, timezones, IdPs, scopes)
├── migrations/
│   └── 001_initial_schema.sql  # Self-contained migration (all-in-one)
└── README.md
```

---

## Schema Overview

### Tenants & Organisations
| Table | Purpose |
|---|---|
| `tenants` | Root tenant record with plan, security settings, regional config |
| `tenant_domains` | Custom domain mapping per tenant |
| `tenant_regional_settings` | Region-specific auth rules and regulations |

### Users & Credentials
| Table | Purpose |
|---|---|
| `users` | Core user record with encrypted PII (email, phone, name) |
| `user_passwords` | Password history with Argon2id/bcrypt/scrypt hashes |
| `user_roles` | Role assignments with optional expiry |

### Applications
| Table | Purpose |
|---|---|
| `applications` | OAuth client registrations with PKCE, redirect URIs |
| `application_scopes` | Scope grants per application |

### Multi-Factor Authentication
| Table | Purpose |
|---|---|
| `mfa_devices` | TOTP secrets, WebAuthn credentials, SMS/Email/Push configs |
| `mfa_recovery_codes` | Hashed backup codes |
| `mfa_challenges` | In-progress MFA verification challenges |

### Sessions & Devices
| Table | Purpose |
|---|---|
| `sessions` | Auth sessions with token hashes, MFA status, geo-info |
| `devices` | Trusted device registry with fingerprinting |

### OAuth 2.0 / OIDC
| Table | Purpose |
|---|---|
| `oauth_scopes` | Scope definitions per tenant |
| `oauth_authorization_codes` | Short-lived PKCE authorization codes |
| `oauth_tokens` | Access tokens, ID tokens, device codes |
| `oauth_refresh_tokens` | Refresh tokens with rotation tracking |

### API Security
| Table | Purpose |
|---|---|
| `api_keys` | Prefixed, hashed API keys with scope control |
| `ip_allowlist` | CIDR-based IP allowlisting |
| `ip_blocklist` | Blocked IPs with optional expiry |

### Identity Providers & SSO
| Table | Purpose |
|---|---|
| `identity_providers` | Generic IdP config (Google, GitHub, SAML, OIDC, LDAP…) |
| `oidc_configurations` | OpenID Connect provider details |
| `saml_configurations` | SAML 2.0 SP + IdP metadata |
| `federated_identities` | User ↔ external identity mapping |
| `sso_sessions` | Cross-app SSO session tracking |
| `sso_session_applications` | Apps participating in an SSO session |

### Localization
| Table | Purpose |
|---|---|
| `languages` | ISO 639-1 language registry (30+ languages) |
| `timezones` | IANA timezone registry (50+ zones) |
| `user_localization_preferences` | Per-user locale, timezone, date/currency formats |
| `ui_translations` | Multi-language UI strings per tenant |

### Audit & Compliance
| Table | Purpose |
|---|---|
| `audit_logs` | Partitioned audit log (40+ event types) |
| `security_events` | Security anomalies with risk scoring |
| `user_consents` | GDPR consent lifecycle management |
| `data_retention_policies` | Automated retention/anonymization rules |
| `pii_deletion_requests` | Right-to-erasure request tracking |
| `data_export_requests` | Data portability request tracking |
| `pii_field_registry` | Data classification catalogue |

### Utilities
| Table | Purpose |
|---|---|
| `password_reset_tokens` | Single-use password reset links |
| `magic_links` | Passwordless login links |
| `email_verification_tokens` | Email address verification |
| `webhooks` | Event webhook configurations |
| `webhook_deliveries` | Webhook delivery attempts and results |

---

## Getting Started

### Prerequisites

- PostgreSQL 15+
- Extensions: `pgcrypto`, `uuid-ossp`, `pg_trgm`, `btree_gist`

### Quickstart (fresh database)

```bash
# Create the database
createdb auth_framework

# Option A: Apply the self-contained migration (recommended)
psql -d auth_framework -f migrations/001_initial_schema.sql

# Option B: Apply files individually in order
psql -d auth_framework \
  -f extensions.sql \
  -f enums.sql \
  -f functions.sql \
  -f schema.sql \
  -f triggers.sql \
  -f indexes.sql \
  -f views.sql \
  -f rls_policies.sql \
  -f seed_data.sql
```

### Application Connection

Set these session-level variables on every connection so RLS policies work correctly:

```sql
-- Set the active tenant (required for all RLS policies)
SET app.current_tenant_id = '018f4d7e-7c00-7000-8000-000000000001';

-- Set the authenticated user (for user-scoped policies)
SET app.current_user_id = '018f4d7e-7c00-7001-8001-000000000002';

-- Set the user's role (for admin vs end-user access)
SET app.current_role = 'end_user';  -- or 'tenant_admin', 'super_admin'

-- Set the PII encryption master key (for encrypt_pii / decrypt_pii)
SET app.pii_master_key = 'your-256-bit-master-secret';
```

> **Production note:** Never store the master key in application code. Retrieve it at startup from AWS Secrets Manager, HashiCorp Vault, or equivalent.

---

## Security Architecture

### PII Encryption

Sensitive fields (email, phone, name) are stored encrypted using **pgcrypto AES-256**:

```sql
-- Per-tenant encryption key derived from master secret
SELECT encrypt_pii('user@example.com', tenant_id);   -- → BYTEA ciphertext
SELECT decrypt_pii(email_encrypted, tenant_id);       -- → 'user@example.com'

-- HMAC-based hash for equality lookups (no plaintext in indexes)
SELECT hmac_sha256('user@example.com', tenant_id);    -- → hex digest
```

### Row-Level Security

Every table has at least one **RESTRICTIVE** RLS policy that enforces tenant isolation:

```sql
-- Automatically applied to every query when RLS is enabled
-- Users only see rows belonging to their current_tenant_id
SELECT * FROM users;  -- implicitly filtered to current tenant
```

### Password Security

- Passwords stored as **Argon2id** hashes (configurable: bcrypt, scrypt, pbkdf2)
- Password history enforced via trigger (prevents reuse of last 5 passwords)
- Account lockout after configurable failed login attempts
- Brute-force detection triggers security events automatically

---

## Compliance

### GDPR (EU)

| Requirement | Implementation |
|---|---|
| Consent management | `user_consents` table with full lifecycle |
| Right to erasure | `pii_deletion_requests` + `fn_process_deletion_request()` |
| Right to data portability | `data_export_requests` with JSON/CSV/XML export |
| Data minimisation | `pii_field_registry` catalogues what is collected |
| Retention limits | `data_retention_policies` + `fn_run_retention_cleanup()` |
| Audit trail | Partitioned `audit_logs` with 40+ event types |
| Data residency | `data_residency_region` on tenants + regional settings |

### US Regulations (CCPA, HIPAA, PCI-DSS)

| Regulation | Implementation |
|---|---|
| CCPA | Consent types include `data_sharing`, `cross_border_transfer` |
| HIPAA | `data_classification` enum includes `phi`; encryption required flag |
| PCI-DSS | `data_classification` includes `financial`; audit logging |
| SOX | Immutable audit log partitions; access control via RLS |

### eIDAS (EU)

- Strong authentication support via WebAuthn / hardware keys
- SAML 2.0 with signed and encrypted assertions
- Session assurance levels tracked in `authn_context`

---

## Localization

### Supported Languages (seed data)

English, Spanish, French, German, Portuguese, Italian, Dutch, Polish, Swedish, Danish, Finnish, Norwegian, Russian, Ukrainian, Czech, Romanian, Hungarian, Turkish, Japanese, Korean, Chinese (Simplified & Traditional), Arabic (RTL), Hebrew (RTL), Persian (RTL), Hindi, Thai, Indonesian, Malay, Vietnamese.

### Timezone Support

50+ IANA timezone zones across Americas, Europe, Asia/Pacific, Africa, and Middle East (seed data).

### Per-User Preferences

```sql
-- User's locale preferences
SELECT date_format, time_format, currency_code, number_format
FROM user_localization_preferences
WHERE user_id = $1;
```

---

## Performance

### UUID v7 Indexes

UUID v7 keys are inserted in **time-sorted order**, which means:
- B-tree index pages fill sequentially → no random-access page splits
- Hot pages stay in buffer cache → fewer disk reads
- Range scans on `id` naturally align with time ranges

### Key Indexes

| Query Pattern | Index |
|---|---|
| User by email | `idx_users_email_hash` (HMAC hash lookup) |
| Active sessions | `idx_sessions_user_active` (partial: status='active') |
| Token lookup | `idx_oauth_tokens_hash` |
| API key lookup | `idx_api_keys_hash` |
| Audit by tenant+time | `idx_audit_logs_tenant` |
| Open security events | `idx_security_events_open` (partial: resolved=FALSE) |
| PII deletion queue | `idx_pii_deletion_due` (partial: status IN (…)) |

### Audit Log Partitioning

`audit_logs` is range-partitioned by `occurred_at` (monthly). Old partitions can be detached and archived without any downtime:

```sql
-- Archive the January 2026 partition
ALTER TABLE audit_logs DETACH PARTITION audit_logs_2026_01;
-- The detached partition still exists as a standalone table
```

---

## Configuration Reference

### Session Variables

| Variable | Type | Required | Description |
|---|---|---|---|
| `app.current_tenant_id` | UUID | ✅ | Active tenant ID for RLS |
| `app.current_user_id` | UUID | Conditional | Authenticated user ID for user-scoped RLS |
| `app.current_role` | TEXT | ✅ | Role (`end_user`, `tenant_admin`, `super_admin`) |
| `app.pii_master_key` | TEXT | ✅ | Master secret for PII encryption key derivation |

### Functions Reference

| Function | Returns | Description |
|---|---|---|
| `uuid_generate_v7()` | UUID | Generate a UUID v7 |
| `uuid_v7_to_timestamptz(uuid)` | TIMESTAMPTZ | Extract timestamp from UUID v7 |
| `encrypt_pii(text, uuid)` | BYTEA | Encrypt PII for a tenant |
| `decrypt_pii(bytea, uuid)` | TEXT | Decrypt PII for a tenant |
| `hmac_sha256(text, uuid)` | TEXT | HMAC hash for PII lookup fields |
| `fn_write_audit_log(...)` | UUID | Write an audit log entry |
| `fn_validate_session(text, uuid)` | TABLE | Validate a session token |
| `fn_record_failed_login(uuid, ...)` | VOID | Increment failure counter, lock if needed |
| `fn_reset_failed_logins(uuid)` | VOID | Reset counter on successful login |
| `fn_revoke_user_sessions(uuid, ...)` | INT | Revoke all (or filtered) user sessions |
| `fn_get_user_mfa_devices(uuid)` | TABLE | List active MFA devices for a user |
| `fn_user_has_mfa(uuid)` | BOOLEAN | Check if user has active MFA |
| `fn_generate_recovery_codes(...)` | TABLE | Generate and store new recovery codes |
| `fn_process_deletion_request(uuid)` | VOID | Execute GDPR right-to-erasure |
| `fn_run_retention_cleanup(uuid)` | TABLE | Run retention policy cleanup |
| `fn_expire_sessions()` | INT | Mark expired sessions (scheduled job) |

### Views Reference

| View | Description |
|---|---|
| `v_active_users` | Active non-deleted users |
| `v_user_sessions` | Active sessions with user + app context |
| `v_user_mfa_status` | MFA enrollment summary per user |
| `v_oauth_token_status` | Active OAuth tokens |
| `v_tenant_idp_summary` | IdP configuration summary per tenant |
| `v_user_consent_summary` | Consent status aggregated per user |
| `v_audit_log_recent` | Audit entries from the last 90 days |
| `v_security_event_summary` | Open security events by severity |
| `v_tenant_overview` | Tenant health dashboard |
| `v_pii_deletion_queue` | Pending GDPR deletion requests |
| `v_application_oauth_summary` | OAuth usage per application |

---

## License

This schema is provided as-is for use in your authentication framework. Adapt it to your specific compliance and security requirements.
