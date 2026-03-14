# GDPR Compliance Guide

This document describes how the multi-tenant authentication framework implements GDPR (General Data Protection Regulation) requirements and related privacy regulations.

---

## Table of Contents

1. [Data Inventory](#1-data-inventory)
2. [Legal Bases for Processing](#2-legal-bases-for-processing)
3. [User Consent Management](#3-user-consent-management)
4. [Right to Access](#4-right-to-access)
5. [Right to Erasure](#5-right-to-erasure)
6. [Data Retention Policies](#6-data-retention-policies)
7. [Data Portability](#7-data-portability)
8. [Cross-Border Data Transfers](#8-cross-border-data-transfers)
9. [Breach Notification Process](#9-breach-notification-process)
10. [DPO Appointment Guidance](#10-dpo-appointment-guidance)
11. [CCPA Compliance Notes](#11-ccpa-compliance-notes)
12. [Privacy by Design](#12-privacy-by-design)

---

## 1. Data Inventory

### Personal data categories collected

| Category            | Fields                                              | Purpose                                        | Legal Basis          |
|---------------------|-----------------------------------------------------|------------------------------------------------|----------------------|
| Identity            | first_name, last_name, display_name                 | User identification and personalization        | Contract             |
| Contact             | email_address, phone_number (optional)              | Authentication, notifications                  | Contract             |
| Credentials         | password_hash, mfa_secrets (encrypted)              | Authentication security                         | Contract             |
| Technical           | ip_address, user_agent, device_name                 | Session management, fraud prevention           | Legitimate interest  |
| Behavioral          | last_login_at, session_history, login_count         | Security monitoring, anomaly detection         | Legitimate interest  |
| Preferences         | locale, timezone, notification preferences          | User experience personalization                | Contract             |
| Consent Records     | consent type, granted_at, withdrawn_at              | Compliance evidence                             | Legal obligation     |
| Audit Logs          | event_type, ip_address, user_agent, timestamp       | Security audit trail                           | Legal obligation     |
| OAuth tokens        | access tokens (hashed), refresh tokens (hashed)     | Third-party application authorization          | Consent              |
| SSO Data            | external_id, sso_provider                           | Federated authentication                       | Contract             |

### Data classification

| Classification | Description                              | Examples                                      |
|----------------|------------------------------------------|-----------------------------------------------|
| Sensitive PII  | Encrypted at rest, access logged         | first_name, last_name, phone_number           |
| Standard PII   | Not encrypted at column level; DB encrypted at rest | email, ip_address              |
| Credentials    | Hashed (bcrypt/SHA-256), never stored in plaintext | password_hash, token_hash      |
| Anonymous      | Cannot identify an individual            | Aggregated usage statistics                   |

### Encrypted fields at rest (AES-256-GCM)

The following fields are encrypted at the application layer before being stored in the database:

```
users.first_name_encrypted
users.last_name_encrypted
users.phone_number_encrypted
users.national_id_encrypted
mfa_devices.secret_encrypted
```

Even with direct database access, these fields are unreadable without the application-layer master key.

### Data NOT collected

This framework intentionally does not collect:
- Social Security Numbers or government ID numbers (unless explicitly enabled per tenant)
- Financial card data (never store PCI data in this system)
- Biometric data
- Health data
- Children's data (users must be 16+ by default, configurable per tenant)

---

## 2. Legal Bases for Processing

Under GDPR Article 6, each processing activity must have a documented legal basis:

| Processing Activity              | Legal Basis          | Article  | Notes                                         |
|----------------------------------|----------------------|----------|-----------------------------------------------|
| Account registration             | Contract             | 6(1)(b)  | Necessary to provide the authentication service |
| Login / authentication           | Contract             | 6(1)(b)  | Core service delivery                         |
| Email verification               | Contract             | 6(1)(b)  | Security requirement of the service           |
| Session management               | Contract             | 6(1)(b)  | Maintaining authenticated state               |
| Password reset                   | Contract             | 6(1)(b)  | Account recovery feature                      |
| MFA device management            | Contract             | 6(1)(b)  | Security enhancement                          |
| Audit logging                    | Legal obligation     | 6(1)(c)  | Security event record-keeping                 |
| Fraud / brute-force detection    | Legitimate interest  | 6(1)(f)  | Security of the service and other users       |
| Marketing communications         | Consent              | 6(1)(a)  | Opt-in only, recorded in consents table       |
| Analytics / behavioral tracking  | Consent              | 6(1)(a)  | Opt-in only; disabled by default             |
| Data export / portability        | Legal obligation     | 6(1)(c)  | Responding to DSAR under Article 20           |
| Account deletion                 | Legal obligation     | 6(1)(c)  | Responding to erasure request under Article 17|

### Documenting legal bases in code

```csharp
public enum ProcessingLegalBasis
{
    Contract,           // GDPR Art. 6(1)(b)
    LegalObligation,    // GDPR Art. 6(1)(c)
    LegitimateInterest, // GDPR Art. 6(1)(f)
    Consent             // GDPR Art. 6(1)(a)
}

// Annotate processing operations
[DataProcessing(
    Purpose = "User authentication",
    LegalBasis = ProcessingLegalBasis.Contract,
    DataCategories = new[] { "identity", "credentials" },
    RetentionDays = 365 * 3)]
public async Task<LoginResult> LoginAsync(LoginRequest request, Guid tenantId) { ... }
```

---

## 3. User Consent Management

### Consent table structure

```sql
-- From schema.sql
CREATE TABLE user_consents (
    id              UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    tenant_id       UUID NOT NULL REFERENCES tenants(id),
    consent_type    TEXT NOT NULL,       -- 'terms_of_service', 'marketing', 'analytics'
    version         TEXT NOT NULL,       -- 'v1.0', 'v2.0' (doc version)
    granted         BOOLEAN NOT NULL,
    granted_at      TIMESTAMPTZ,
    withdrawn_at    TIMESTAMPTZ,
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Recording consent at registration

```csharp
public async Task RecordConsentsAsync(Guid userId, Guid tenantId,
    RegisterRequest request, string ipAddress, string userAgent)
{
    var consents = new List<UserConsent>
    {
        new()
        {
            Id = UuidV7.NewUuid(),
            UserId = userId,
            TenantId = tenantId,
            ConsentType = "terms_of_service",
            Version = "v1.0",
            Granted = request.ConsentToTerms,
            GrantedAt = request.ConsentToTerms ? DateTimeOffset.UtcNow : null,
            IpAddress = ipAddress,
            UserAgent = userAgent,
            CreatedAt = DateTimeOffset.UtcNow
        },
        new()
        {
            Id = UuidV7.NewUuid(),
            UserId = userId,
            TenantId = tenantId,
            ConsentType = "marketing",
            Version = "v1.0",
            Granted = request.ConsentToMarketing,
            GrantedAt = request.ConsentToMarketing ? DateTimeOffset.UtcNow : null,
            CreatedAt = DateTimeOffset.UtcNow
        }
    };

    _db.UserConsents.AddRange(consents);
    await _db.SaveChangesAsync();
}
```

### Consent withdrawal

Users can withdraw consent at any time via `PUT /api/users/me/preferences`.

```csharp
public async Task WithdrawConsentAsync(Guid userId, Guid tenantId, string consentType)
{
    var consent = await _db.UserConsents
        .Where(c => c.UserId == userId
            && c.TenantId == tenantId
            && c.ConsentType == consentType
            && c.Granted)
        .OrderByDescending(c => c.CreatedAt)
        .FirstOrDefaultAsync();

    if (consent != null)
    {
        consent.Granted = false;
        consent.WithdrawnAt = DateTimeOffset.UtcNow;
        await _db.SaveChangesAsync();
    }

    // Stop any processing that relied on this consent
    if (consentType == "marketing")
        await _emailService.UnsubscribeAsync(userId);
}
```

### Consent versioning

When terms of service or privacy policy are updated:

1. Increment the document version (e.g., `v1.0` → `v2.0`)
2. On next login, prompt users to review and re-accept updated terms
3. Record the new consent with the new version number
4. Old consent records are preserved for audit purposes (never deleted)

---

## 4. Right to Access

### GDPR Article 15 – Data Subject Access Request (DSAR)

Users can request a complete export of all personal data held about them.

**Endpoint:** `GET /api/users/me/data-export`

### What the export includes

```json
{
  "exportedAt": "2025-01-15T12:00:00Z",
  "dataSubject": {
    "userId": "018e7f4a-1234-7abc-8def-000000000001",
    "email": "user@example.com",
    "firstName": "Jane",
    "lastName": "Doe",
    "createdAt": "2025-01-01T00:00:00Z"
  },
  "profile": {
    "locale": "en-US",
    "timezone": "America/New_York",
    "avatarUrl": null,
    "lastLoginAt": "2025-01-15T10:00:00Z"
  },
  "consents": [
    {
      "consentType": "terms_of_service",
      "version": "v1.0",
      "granted": true,
      "grantedAt": "2025-01-01T00:00:00Z"
    }
  ],
  "sessions": [
    {
      "sessionId": "018e7f4a-2222-7abc-8def-000000000002",
      "createdAt": "2025-01-15T10:00:00Z",
      "ipAddress": "203.0.113.42",
      "deviceName": "Chrome on macOS"
    }
  ],
  "auditLogs": [
    {
      "eventType": "login_success",
      "ipAddress": "203.0.113.42",
      "createdAt": "2025-01-15T10:00:00Z"
    }
  ],
  "oauthAuthorizations": [
    {
      "applicationName": "My App",
      "scopes": ["openid", "profile"],
      "authorizedAt": "2025-01-10T00:00:00Z"
    }
  ]
}
```

### DSAR implementation

```csharp
// Services/DataExportService.cs
public async Task<Guid> RequestExportAsync(Guid userId, Guid tenantId)
{
    var exportId = UuidV7.NewUuid();

    // Queue the export as a background job (may take time for large datasets)
    await _backgroundJobs.EnqueueAsync(new DataExportJob
    {
        ExportId = exportId,
        UserId = userId,
        TenantId = tenantId,
        RequestedAt = DateTimeOffset.UtcNow
    });

    // Log the DSAR request
    await _audit.LogAsync("data_export_requested", userId, tenantId,
        new { exportId });

    return exportId;
}

public async Task ProcessExportAsync(DataExportJob job)
{
    // Collect all data
    var user = await _db.Users.FindAsync(job.UserId);
    var consents = await _db.UserConsents.Where(c => c.UserId == job.UserId).ToListAsync();
    var sessions = await _db.UserSessions.Where(s => s.UserId == job.UserId).ToListAsync();
    var auditLogs = await _db.AuditLogs.Where(l => l.UserId == job.UserId).ToListAsync();

    // Decrypt PII fields for the export
    var export = new UserDataExport
    {
        ExportedAt = DateTimeOffset.UtcNow,
        DataSubject = new
        {
            UserId = user!.Id,
            Email = user.Email,
            FirstName = _encryption.Decrypt(user.FirstNameEncrypted),
            LastName = _encryption.Decrypt(user.LastNameEncrypted),
            CreatedAt = user.CreatedAt
        },
        Consents = consents.Select(MapConsent),
        Sessions = sessions.Select(MapSession),
        AuditLogs = auditLogs.Select(MapAuditLog)
    };

    // Serialize and store securely
    var json = JsonSerializer.Serialize(export, _jsonOptions);
    var downloadToken = await _secureStorage.StoreExportAsync(job.ExportId, json,
        expiresIn: TimeSpan.FromDays(7));

    // Send email with secure download link
    await _emailService.SendDataExportReadyAsync(user.Email, downloadToken);
}
```

### Response time SLA

- Acknowledge the request immediately (HTTP 202 Accepted)
- Complete the export within **30 days** (GDPR Article 12 requirement)
- Target: deliver within **72 hours** for good practice
- Notify the user by email when the export is ready
- Export download links expire after **7 days**

---

## 5. Right to Erasure

### GDPR Article 17 – Right to be Forgotten

**Endpoint:** `POST /api/users/me/delete`

### What deletion means

| Data Type          | Action                                              | Timing          |
|--------------------|-----------------------------------------------------|-----------------|
| Active sessions    | Immediately revoked                                 | Immediate       |
| Access/refresh tokens | Immediately invalidated                          | Immediate       |
| User profile PII   | Overwritten with null/anonymized values             | Within 30 days  |
| Password hash      | Deleted                                             | Within 30 days  |
| MFA secrets        | Deleted                                             | Within 30 days  |
| Audit logs         | User ID replaced with anonymized reference          | Within 30 days  |
| Consent records    | Retained for 7 years (legal obligation)             | Never deleted   |
| Billing records    | Retained for 7 years (tax/accounting obligation)    | Never deleted   |

### Deletion schedule and grace period

```csharp
// Services/DeletionService.cs
public async Task ScheduleDeletionAsync(Guid userId, Guid tenantId,
    DeletionRequest request)
{
    // Revoke all active sessions immediately
    await RevokeAllSessionsAsync(userId, tenantId);

    var scheduledAt = DateTimeOffset.UtcNow.AddDays(30);
    var cancellationDeadline = DateTimeOffset.UtcNow.AddDays(7);

    var deletionRecord = new DataDeletionRequest
    {
        Id = UuidV7.NewUuid(),
        UserId = userId,
        TenantId = tenantId,
        Reason = request.Reason,
        ScheduledAt = scheduledAt,
        CancellationDeadline = cancellationDeadline,
        Status = DeletionStatus.Pending,
        CreatedAt = DateTimeOffset.UtcNow
    };

    _db.DataDeletionRequests.Add(deletionRecord);
    await _db.SaveChangesAsync();

    await _audit.LogAsync("account_deletion_requested", userId, tenantId,
        new { scheduledAt, cancellationDeadline });

    await _emailService.SendDeletionConfirmationAsync(userId, scheduledAt, cancellationDeadline);
}

public async Task ExecuteDeletionAsync(Guid userId, Guid tenantId)
{
    var user = await _db.Users.FindAsync(userId)
        ?? throw new NotFoundException("User not found.");

    // Anonymize rather than hard-delete to preserve referential integrity
    user.FirstNameEncrypted = _encryption.Encrypt("[deleted]");
    user.LastNameEncrypted = _encryption.Encrypt("[deleted]");
    user.PhoneNumberEncrypted = null;
    user.Email = $"deleted_{userId}@deleted.invalid";
    user.PasswordHash = null;
    user.Status = UserStatus.Deleted;
    user.DeletedAt = DateTimeOffset.UtcNow;

    // Remove MFA secrets
    var mfaDevices = await _db.MfaDevices.Where(d => d.UserId == userId).ToListAsync();
    _db.MfaDevices.RemoveRange(mfaDevices);

    // Anonymize audit log references
    await _db.Database.ExecuteSqlInterpolatedAsync(
        $"UPDATE audit_logs SET user_id = NULL, metadata = metadata - 'email' WHERE user_id = {userId}");

    await _db.SaveChangesAsync();

    await _audit.LogAsync("account_deleted", null, tenantId,
        new { originalUserId = userId, deletedAt = DateTimeOffset.UtcNow });
}
```

### Grounds to refuse erasure

Erasure requests may be denied if the data is needed for:
- Compliance with a legal obligation (Article 17(3)(b))
- Legal claims (Article 17(3)(e))
- Tax/financial record retention (varies by jurisdiction)

When refusing, document the reason and notify the user with the grounds for refusal.

---

## 6. Data Retention Policies

### data_retention_policies table

```sql
-- From schema.sql
CREATE TABLE data_retention_policies (
    id              UUID PRIMARY KEY DEFAULT generate_uuid_v7(),
    tenant_id       UUID REFERENCES tenants(id),  -- NULL = global default
    data_category   TEXT NOT NULL,
    retention_days  INTEGER NOT NULL,
    legal_basis     TEXT,
    auto_delete     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### Default retention periods

| Data Category          | Default Retention | Legal Basis                    | Auto-Delete |
|------------------------|-------------------|--------------------------------|-------------|
| Active user accounts   | Indefinite        | Contract                       | No          |
| Deleted user accounts  | 30 days           | GDPR Article 17                | Yes         |
| User sessions          | 90 days           | Security monitoring            | Yes         |
| Audit logs             | 365 days          | Security / legal obligation    | Yes         |
| Security events        | 365 days          | Legal obligation               | Yes         |
| Refresh tokens         | 31 days           | Contract (session lifetime)    | Yes         |
| OAuth auth codes       | 10 minutes        | OAuth 2.0 spec                 | Yes         |
| OAuth access tokens    | 15 minutes + 7d   | Contract                       | Yes         |
| Password reset tokens  | 1 hour            | Security                       | Yes         |
| Email verify tokens    | 24 hours          | Security                       | Yes         |
| Consent records        | 7 years           | Legal obligation (evidence)    | No          |
| Export requests        | 90 days           | GDPR Article 15                | Yes         |
| Deletion requests      | 7 years           | Legal obligation (evidence)    | No          |

### Automated cleanup

The `cleanup_expired_sessions()` function (in `functions.sql`) is scheduled via `pg_cron` to run nightly:

```sql
-- Schedule in seed_data.sql
SELECT cron.schedule('nightly-cleanup', '0 2 * * *', $$
    SELECT cleanup_expired_sessions();
    SELECT cleanup_expired_tokens();
    SELECT cleanup_old_audit_logs();
    SELECT execute_pending_deletions();
$$);
```

Or schedule via a .NET background service:

```csharp
// BackgroundServices/RetentionCleanupService.cs
public class RetentionCleanupService : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            // Run at 2:00 AM UTC daily
            var nextRun = GetNextRunTime(TimeOnly.FromTimeSpan(TimeSpan.FromHours(2)));
            await Task.Delay(nextRun - DateTimeOffset.UtcNow, stoppingToken);

            await _db.Database.ExecuteSqlRawAsync("SELECT cleanup_expired_sessions()");
            await _db.Database.ExecuteSqlRawAsync("SELECT execute_pending_deletions()");

            _logger.LogInformation("Data retention cleanup completed at {Time}",
                DateTimeOffset.UtcNow);
        }
    }
}
```

---

## 7. Data Portability

### GDPR Article 20 – Right to Data Portability

The export format is **JSON**, chosen because:
- Machine-readable and structured
- Human-readable with any text editor
- Interoperable – most authentication systems can consume JSON
- Includes all data categories in a single file

### Export structure

```
user-data-export-{userId}-{timestamp}.json
├── profile           (identity, contact, preferences)
├── sessions          (session history)
├── consents          (consent records)
├── mfaDevices        (device names only, no secrets)
├── oauthApps         (authorized applications and scopes)
├── auditLogs         (security event history)
└── metadata          (export info, schema version)
```

### Machine-readable schema

The export JSON includes a `$schema` reference for automated processing:

```json
{
  "$schema": "https://auth.example.com/schemas/data-export/v1.json",
  "schemaVersion": "1.0",
  "exportedAt": "2025-01-15T12:00:00Z",
  ...
}
```

---

## 8. Cross-Border Data Transfers

### data_residency field on tenants

```sql
-- tenants table includes
data_residency TEXT NOT NULL DEFAULT 'us-east-1'
-- Supported values: 'us-east-1', 'eu-west-1', 'ap-southeast-1', etc.
```

### Transfer mechanisms

| Transfer Scenario                        | Mechanism                        | Notes                                   |
|------------------------------------------|----------------------------------|-----------------------------------------|
| EU → US (standard)                       | Standard Contractual Clauses     | EU-US Data Privacy Framework approved   |
| EU → US (Privacy Shield successor)       | EU-US DPF                        | Self-certification required             |
| EU internal                              | No transfer mechanism needed     | Same legal jurisdiction                 |
| EU → UK                                  | UK GDPR adequacy decision        | UK-GDPR post-Brexit                     |
| EU → Switzerland                         | Swiss adequacy decision          | Approved under GDPR                     |
| Any → Country without adequacy decision  | SCCs + Transfer Impact Assessment| Document per Article 46                 |

### Tenant data residency enforcement

```csharp
// When provisioning a new tenant, deploy the database to the correct region
public async Task<Tenant> CreateTenantAsync(CreateTenantRequest request)
{
    var allowedRegions = new[] { "us-east-1", "eu-west-1", "ap-southeast-1" };
    if (!allowedRegions.Contains(request.DataResidency))
        throw new ValidationException("Invalid data_residency region.");

    // In production, route to the correct regional database
    var connectionString = _regionalConfig.GetConnectionString(request.DataResidency);

    var tenant = new Tenant
    {
        Id = UuidV7.NewUuid(),
        DataResidency = request.DataResidency,
        // ...
    };
    // ...
}
```

---

## 9. Breach Notification Process

### GDPR Article 33 – 72-hour notification requirement

A personal data breach must be reported to the supervisory authority within **72 hours** of becoming aware of it (if it is likely to result in a risk to individuals' rights and freedoms).

### Breach severity assessment

| Breach Type                          | Risk Level | SA Notification | User Notification |
|--------------------------------------|------------|-----------------|-------------------|
| Encrypted PII exposed                | Low-Medium | Yes (within 72h) | May not be required |
| Plaintext PII exposed                | High       | Yes (within 72h) | Yes (without delay) |
| Password hashes (bcrypt) exposed     | Medium     | Yes             | Recommend password reset |
| Auth tokens exposed                  | High       | Yes             | Yes + revoke tokens |
| Authentication bypass discovered     | Critical   | Yes             | Yes + force logouts |
| Audit logs accessed without auth     | Medium     | Yes             | May not be required |

### Internal breach response workflow

```
[Detection]
    │
    ▼
[0h]  Incident declared → Assign incident commander
    │
    ▼
[1h]  Scope assessment → Which tenants/users affected?
    │                    What data categories exposed?
    │
    ▼
[4h]  Contain breach → Revoke tokens, patch vulnerability
    │
    ▼
[24h] Preliminary severity assessment
    │
    ▼
[48h] Draft supervisory authority notification
    │
    ▼
[72h] Submit notification to lead supervisory authority
    │
    ▼
[72h+] Notify affected users if high risk to their rights
    │
    ▼
[30d] Full incident report and remediation plan
```

### Supervisory authority notification contents (Article 33(3))

1. Nature of the breach (categories of data, approximate number of records)
2. Name and contact details of the DPO
3. Likely consequences of the breach
4. Measures taken or proposed to address the breach
5. If notification is delayed beyond 72 hours, reasons for the delay

### User notification template

When users must be notified (Article 34), include:
- Clear description of what happened
- Categories of personal data affected
- Name and contact details of the DPO
- Recommended steps the user should take (e.g., change password)
- What the organization is doing to address it

---

## 10. DPO Appointment Guidance

### When is a DPO required?

Under GDPR Article 37, a Data Protection Officer is **mandatory** if:
- You are a public authority or body
- You carry out **large-scale systematic monitoring** of individuals (e.g., tracking user behavior across tenants at scale)
- You process **special category data** or criminal conviction data on a large scale

For a multi-tenant authentication framework:
- **SaaS with fewer than ~50,000 users:** DPO likely not mandatory but recommended
- **SaaS with 50,000+ users or processing behavioral data:** DPO strongly recommended
- **Enterprise with HR, health, or financial tenant data:** DPO required

### DPO responsibilities for this framework

| Responsibility            | Action                                                         |
|---------------------------|----------------------------------------------------------------|
| Records of Processing     | Maintain ROPA (Record of Processing Activities) under Art. 30 |
| DSAR handling             | Oversee data export and deletion request processes            |
| Privacy assessments       | Conduct DPIAs for new high-risk features                       |
| Breach notification       | Lead 72-hour notification process                              |
| Staff training            | Ensure developers understand privacy-by-design requirements    |
| Vendor assessment         | Review DPAs with sub-processors (PostgreSQL hosting, email)   |

### DPO contact in API responses

The DPO contact should be discoverable:

```json
// GET /api/.well-known/privacy
{
  "dpoEmail": "dpo@example.com",
  "privacyPolicyUrl": "https://example.com/privacy",
  "dataSubjectRightsUrl": "https://example.com/privacy/rights",
  "supervisoryAuthority": "ICO (UK) / DPA (relevant EU member state)"
}
```

---

## 11. CCPA Compliance Notes

The California Consumer Privacy Act (CCPA) / CPRA applies to businesses meeting certain thresholds serving California residents.

### CCPA rights mapped to framework features

| CCPA Right                     | GDPR Equivalent  | Framework Implementation                      |
|--------------------------------|------------------|-----------------------------------------------|
| Right to Know (access)         | Article 15       | `GET /api/users/me/data-export`               |
| Right to Delete                | Article 17       | `POST /api/users/me/delete`                   |
| Right to Correct               | Article 16       | `PATCH /api/users/me`                         |
| Right to Opt-Out of Sale       | N/A              | `PUT /api/users/me/preferences` (do_not_sell) |
| Right to Non-Discrimination    | N/A              | Service not degraded for exercising rights    |
| Right to Limit Sensitive PI Use| Article 9        | Sensitive PI processing consent flags         |

### "Do Not Sell or Share" implementation

```csharp
// Add to user preferences
public class UserPreferences
{
    public bool DoNotSell { get; set; }       // CCPA opt-out
    public bool DoNotShare { get; set; }      // CPRA sharing opt-out
    public bool LimitSensitiveDataUse { get; set; } // CPRA sensitive data
}
```

### CCPA vs GDPR key differences

| Aspect                     | GDPR                        | CCPA/CPRA                         |
|----------------------------|-----------------------------|-----------------------------------|
| Opt-in consent required    | Yes (for non-contract processing) | No (opt-out model)            |
| Data subject rights        | 8 rights                    | 6 rights                          |
| Applies to                 | All EU/EEA data subjects    | California residents (thresholds) |
| Fines                      | Up to 4% of global turnover | $7,500 per intentional violation  |
| Response deadline          | 30 days                     | 45 days (extendable to 90)        |

---

## 12. Privacy by Design

GDPR Article 25 requires "data protection by design and by default." The following principles are built into this framework:

### 1. Data minimisation

Only collect data necessary for the stated purpose:
- Phone number field is **optional** and only collected if explicitly enabled per tenant
- Device fingerprinting limited to user_agent, IP, and device_name – no canvas fingerprinting
- No third-party analytics SDKs embedded in the auth flow by default

### 2. Purpose limitation

Data collected for authentication is not used for other purposes:
- Audit logs are used only for security monitoring, not behavioral profiling
- IP addresses are used for session tracking and fraud detection, not geolocation profiling

### 3. Storage limitation

Data is automatically purged after its retention period via background jobs (see [Section 6](#6-data-retention-policies)).

### 4. Integrity and confidentiality

- PII encrypted at application layer (AES-256-GCM)
- Passwords hashed with bcrypt (work factor 12)
- TOTP secrets encrypted at rest
- Database encrypted at rest (platform-level)
- Transport encrypted via TLS 1.3

### 5. Pseudonymisation

Audit logs reference `user_id` (UUID) rather than email or name. After account deletion, `user_id` is nullified in audit logs, making them truly anonymous.

```csharp
// Audit log entry uses UUID reference, not PII
await _audit.LogAsync("login_success", userId, tenantId,
    new { sessionId, mfaUsed }); // email NOT included
```

### 6. Accuracy

- Email change requires re-verification
- Profile updates are logged with before/after values for audit purposes
- SSO attribute mapping updates user profile on each login (configurable per tenant)

### 7. Consent before processing

No optional data processing occurs before consent is recorded:

```csharp
// Check consent before sending marketing emails
var hasMarketingConsent = await _db.UserConsents
    .AnyAsync(c => c.UserId == userId && c.ConsentType == "marketing"
        && c.Granted && c.WithdrawnAt == null);

if (!hasMarketingConsent)
    return; // Skip marketing processing
```

### 8. Default privacy settings

The most privacy-preserving settings are applied by default:
- `consentToMarketing`: `false` by default
- `profileVisible`: `false` by default
- `activityTracking`: `false` by default
- Session duration: 15 minutes (short by default, configurable up)

### 9. DPIA (Data Protection Impact Assessment)

Conduct a DPIA before deploying any of the following features:
- Behavioral analytics or user profiling
- AI/ML-based anomaly detection that profiles individuals
- New data collection fields
- Cross-tenant data aggregation for reporting
- Any new special category data processing

---

*Last updated: 2025-01-15 | Framework version: 1.0.0*  
*This document does not constitute legal advice. Consult a qualified GDPR legal specialist for your specific circumstances.*
