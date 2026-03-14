# Security Hardening Guide

This document covers security hardening recommendations and implemented controls for the multi-tenant authentication framework.

---

## Table of Contents

1. [JWT Security](#1-jwt-security)
2. [Password Security](#2-password-security)
3. [MFA Security](#3-mfa-security)
4. [Rate Limiting](#4-rate-limiting)
5. [CORS Configuration](#5-cors-configuration)
6. [SQL Injection Prevention](#6-sql-injection-prevention)
7. [Tenant Isolation](#7-tenant-isolation)
8. [PII Encryption](#8-pii-encryption)
9. [Session Security](#9-session-security)
10. [Security Headers](#10-security-headers)
11. [Audit Logging](#11-audit-logging)
12. [Incident Response](#12-security-incident-response)
13. [Dependency Scanning](#13-dependency-scanning)

---

## 1. JWT Security

### Algorithm selection

| Environment | Algorithm | Reason                                                        |
|-------------|-----------|---------------------------------------------------------------|
| Production  | RS256     | Asymmetric – only the auth server needs the private key       |
| Development | HS256     | Symmetric – simpler local setup, never use in production      |

**Why RS256 in production:** Resource servers (microservices) can validate tokens using only the public key. The private key never leaves the auth server, reducing blast radius if a service is compromised.

```csharp
// Production: RS256 with RSA 4096-bit key
var rsa = RSA.Create();
rsa.ImportFromPem(File.ReadAllText(config["Jwt:PrivateKeyPath"]!));

var tokenHandler = new JwtSecurityTokenHandler();
var tokenDescriptor = new SecurityTokenDescriptor
{
    Subject = new ClaimsIdentity(claims),
    Expires = DateTime.UtcNow.AddMinutes(15),
    Issuer = config["Jwt:Issuer"],
    Audience = config["Jwt:Audience"],
    SigningCredentials = new SigningCredentials(
        new RsaSecurityKey(rsa), SecurityAlgorithms.RsaSha256)
};
```

### Token expiry

| Token Type    | Lifetime    | Rationale                                        |
|---------------|-------------|--------------------------------------------------|
| Access Token  | 15 minutes  | Short-lived to limit exposure if intercepted     |
| Refresh Token | 30 days     | Stored securely, rotated on each use             |
| MFA Token     | 5 minutes   | One-time use for completing MFA challenge        |
| Email Verify  | 24 hours    | Long enough for async email delivery             |
| Password Reset| 1 hour      | Short window limits phishing window              |

### Token rotation

Refresh tokens are rotated on every use:

```csharp
public async Task<TokenPair> RefreshAsync(string refreshToken)
{
    var tokenHash = HashToken(refreshToken);

    // Detect refresh token reuse (potential theft)
    var session = await _db.UserSessions
        .FirstOrDefaultAsync(s => s.RefreshTokenHash == tokenHash);

    if (session == null)
    {
        // Token was already used – potential replay attack
        // Revoke ALL sessions for this user as a precaution
        await RevokeAllUserSessionsAsync(suspectedUserId);
        throw new UnauthorizedException("invalid_token", "Refresh token reuse detected.");
    }

    // Rotate: invalidate old token, issue new pair
    session.RefreshTokenHash = HashToken(GenerateRefreshToken());
    session.RefreshTokenExpiresAt = DateTimeOffset.UtcNow.AddDays(30);
    await _db.SaveChangesAsync();
}
```

### JWT claims to always include

```json
{
  "sub":        "018e7f4a-1234-7abc-8def-000000000001",
  "iss":        "https://auth.example.com",
  "aud":        "https://api.example.com",
  "iat":        1737027900,
  "exp":        1737028800,
  "jti":        "018e7f4a-9999-7abc-8def-000000000009",
  "tenant_id":  "018e7f4a-0000-7abc-8def-000000000000",
  "session_id": "018e7f4a-2222-7abc-8def-000000000002",
  "roles":      ["user"],
  "mfa":        true
}
```

- Always validate `iss`, `aud`, `exp`, and `nbf`
- Use `jti` (JWT ID) to enable token revocation via a deny-list
- Never store sensitive PII (passwords, SSNs) in JWT claims – claims are base64-decoded, not encrypted
- Set `ClockSkew` to ≤30 seconds, not the default 5 minutes

### JWKS endpoint

Expose a public key endpoint for RS256 token validation:

```csharp
app.MapGet("/.well-known/jwks.json", (ITokenService tokenService) =>
    Results.Ok(tokenService.GetJwks()));
```

---

## 2. Password Security

### Hashing with bcrypt

```csharp
// Work factor 12 is the recommended minimum for 2024+
// Benchmark: aim for ~250ms hash time on your production hardware
const int WorkFactor = 12;

string Hash(string password) =>
    BCrypt.Net.BCrypt.HashPassword(password, WorkFactor);

bool Verify(string password, string hash) =>
    BCrypt.Net.BCrypt.Verify(password, hash);
```

**Choosing the work factor:**

| Work Factor | Approx time (modern CPU) | Recommendation      |
|-------------|--------------------------|---------------------|
| 10          | ~60ms                    | Minimum acceptable  |
| 12          | ~250ms                   | **Recommended**     |
| 14          | ~1s                      | High-security use   |

Re-hash on login when the configured work factor increases:

```csharp
if (BCrypt.Net.BCrypt.PasswordNeedsRehash(user.PasswordHash, WorkFactor))
{
    user.PasswordHash = BCrypt.Net.BCrypt.HashPassword(plainPassword, WorkFactor);
    await _db.SaveChangesAsync();
}
```

### Password requirements

Enforce the following minimum requirements:

| Requirement             | Value           |
|-------------------------|-----------------|
| Minimum length          | 12 characters   |
| Maximum length          | 128 characters  |
| Uppercase letters       | ≥1              |
| Lowercase letters       | ≥1              |
| Digits                  | ≥1              |
| Special characters      | ≥1              |
| Common passwords        | Blocked (HIBP)  |
| Password history        | Last 5 blocked  |

```csharp
// Check against Have I Been Pwned API (k-anonymity model)
public async Task<bool> IsPasswordPwnedAsync(string password)
{
    var hash = Convert.ToHexString(SHA1.HashData(Encoding.UTF8.GetBytes(password)));
    var prefix = hash[..5];
    var suffix = hash[5..];

    var response = await _httpClient.GetStringAsync(
        $"https://api.pwnedpasswords.com/range/{prefix}");

    return response.Contains(suffix, StringComparison.OrdinalIgnoreCase);
}
```

### Password reset security

- Reset tokens are single-use and expire after 1 hour
- Sending the reset email always returns HTTP 200 (prevents user enumeration)
- After reset, revoke ALL active sessions
- Notify the user's email that a password reset occurred

---

## 3. MFA Security

### TOTP recommendations

- Use **30-second** time steps (RFC 6238 default)
- Allow ±1 step tolerance for clock skew (90-second window total)
- Track used TOTP codes to prevent replay within the same window:

```csharp
// Store used codes with 90-second TTL in Redis or the database
var codeKey = $"totp:used:{deviceId}:{code}";
if (await _cache.ExistsAsync(codeKey))
    throw new BadRequestException("mfa_code_invalid", "Code has already been used.");

await _cache.SetAsync(codeKey, "1", TimeSpan.FromSeconds(90));
```

- Encrypt TOTP secrets at rest using AES-256-GCM
- The TOTP secret is shown only once during enrollment (not retrievable later)

### Backup codes

- Generate 8 codes of 9 characters each (sufficient entropy: 8 × 36^9 ≈ 2^46)
- Hash backup codes with bcrypt (work factor 4 is acceptable – codes are randomly generated)
- Each backup code is single-use; mark as used immediately
- Regenerating codes invalidates all previous codes
- Warn users when fewer than 3 backup codes remain

### MFA bypass prevention

- MFA challenges expire after 5 minutes
- Bind the MFA challenge token to the original IP address; warn if different IP completes it
- Require current password to remove an MFA device
- Send email notification when MFA is enrolled, disabled, or a device is removed

---

## 4. Rate Limiting

### Configuration in appsettings.json

```json
{
  "IpRateLimiting": {
    "EnableEndpointRateLimiting": true,
    "StackBlockedRequests": false,
    "RealIpHeader": "X-Forwarded-For",
    "HttpStatusCode": 429,
    "GeneralRules": [
      {
        "Endpoint": "POST:/api/auth/login",
        "Period": "1m",
        "Limit": 10
      },
      {
        "Endpoint": "POST:/api/auth/register",
        "Period": "1m",
        "Limit": 5
      },
      {
        "Endpoint": "POST:/api/auth/password-reset",
        "Period": "1h",
        "Limit": 5
      },
      {
        "Endpoint": "POST:/api/mfa/verify",
        "Period": "1m",
        "Limit": 10
      },
      {
        "Endpoint": "*",
        "Period": "1m",
        "Limit": 300
      }
    ]
  }
}
```

### Progressive delays on failed logins

```csharp
// Exponential backoff: 2^attempts seconds up to 30 minutes
var delaySeconds = Math.Min(Math.Pow(2, failedAttempts), 1800);
await Task.Delay(TimeSpan.FromSeconds(delaySeconds));
```

### Account lockout policy

| Failed Attempts | Action                                |
|-----------------|---------------------------------------|
| 5               | Warn user via email                   |
| 10              | Lock account for 30 minutes           |
| 20              | Lock account indefinitely (admin unlock required) |

---

## 5. CORS Configuration

```csharp
// Program.cs
builder.Services.AddCors(options =>
{
    options.AddPolicy("ProductionPolicy", policy =>
    {
        // Never use AllowAnyOrigin with AllowCredentials
        policy.WithOrigins(
                "https://app.example.com",
                "https://admin.example.com")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials()    // Required for cookies
              .SetPreflightMaxAge(TimeSpan.FromMinutes(10));
    });

    options.AddPolicy("DevelopmentPolicy", policy =>
    {
        policy.WithOrigins("http://localhost:3000", "http://localhost:5173")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials();
    });
});

var corsPolicy = app.Environment.IsDevelopment()
    ? "DevelopmentPolicy" : "ProductionPolicy";
app.UseCors(corsPolicy);
```

### CORS rules

- **Never** use `AllowAnyOrigin()` with `AllowCredentials()`
- Maintain an explicit allow-list of origins; reject `null` origins
- Validate `Origin` header server-side for sensitive operations
- Restrict allowed methods to only those needed (`GET`, `POST`, `PATCH`, `DELETE`)

---

## 6. SQL Injection Prevention

### EF Core parameterized queries

EF Core automatically parameterizes all LINQ queries:

```csharp
// Safe: EF Core translates this to a parameterized query
var user = await _db.Users
    .FirstOrDefaultAsync(u => u.Email == email && u.TenantId == tenantId);
// SQL: SELECT * FROM users WHERE email = @p0 AND tenant_id = @p1
```

### Raw SQL – always use parameters

```csharp
// Safe: use FormattableString interpolation (EF Core converts to parameters)
var users = await _db.Users
    .FromSqlInterpolated($"SELECT * FROM users WHERE email = {email}")
    .ToListAsync();

// Safe: explicit parameters
var users = await _db.Users
    .FromSqlRaw("SELECT * FROM users WHERE email = @email",
        new NpgsqlParameter("@email", email))
    .ToListAsync();

// UNSAFE: never do this
var users = await _db.Users
    .FromSqlRaw($"SELECT * FROM users WHERE email = '{email}'") // SQL INJECTION RISK
    .ToListAsync();
```

### Stored procedures for sensitive operations

Use PostgreSQL functions for sensitive operations (token hashing, audit writes) to further reduce injection surface:

```sql
-- functions.sql
CREATE OR REPLACE FUNCTION record_login_attempt(
    p_user_id UUID,
    p_tenant_id UUID,
    p_success BOOLEAN,
    p_ip INET
) RETURNS VOID AS $$
BEGIN
    INSERT INTO audit_logs (id, user_id, tenant_id, event_type, ip_address, created_at)
    VALUES (generate_uuid_v7(), p_user_id, p_tenant_id,
            CASE WHEN p_success THEN 'login_success' ELSE 'login_failure' END,
            p_ip, NOW());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

---

## 7. Tenant Isolation

### Three-layer defence-in-depth approach

```
HTTP Request
    │
    ▼
┌─────────────────────────────┐
│ TenantMiddleware             │  Layer 1: Validate X-Tenant-ID header
│ (validates tenant is active) │           Reject unknown tenants early
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ EF Core Global Query Filters │  Layer 2: Automatic WHERE tenant_id = @id
│ (ORM-level isolation)        │           on every LINQ query
└──────────────┬──────────────┘
               │
               ▼
┌─────────────────────────────┐
│ PostgreSQL Row Level Security│  Layer 3: Database enforces isolation
│ (RLS policies)               │           even for direct DB connections
└─────────────────────────────┘
```

### RLS policy template

```sql
-- rls_policies.sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE users FORCE ROW LEVEL SECURITY;  -- Applies to table owner too

CREATE POLICY users_tenant_isolation ON users
    AS PERMISSIVE
    FOR ALL
    TO application_role
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid);
```

### EF Core global query filter setup

```csharp
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    // Apply to all tenant-scoped entities automatically
    foreach (var entityType in modelBuilder.Model.GetEntityTypes())
    {
        if (typeof(ITenantEntity).IsAssignableFrom(entityType.ClrType))
        {
            modelBuilder.Entity(entityType.ClrType)
                .HasQueryFilter(BuildTenantFilter(entityType.ClrType));
        }
    }
}

private LambdaExpression BuildTenantFilter(Type entityType)
{
    var param = Expression.Parameter(entityType, "e");
    var tenantIdProp = Expression.Property(param, "TenantId");
    var currentTenantId = Expression.Constant(_currentTenantId);
    var body = Expression.Equal(tenantIdProp, currentTenantId);
    return Expression.Lambda(body, param);
}
```

---

## 8. PII Encryption

### AES-256-GCM implementation

AES-256-GCM is used for authenticated encryption of sensitive PII fields (names, phone numbers, national IDs).

```csharp
// Services/EncryptionService.cs
public class EncryptionService : IEncryptionService
{
    private readonly byte[] _masterKey;

    public EncryptionService(IConfiguration config)
    {
        _masterKey = Convert.FromBase64String(config["Encryption:MasterKeyBase64"]!);
        if (_masterKey.Length != 32)
            throw new InvalidOperationException("AES-256 key must be exactly 32 bytes.");
    }

    public string Encrypt(string plaintext)
    {
        if (string.IsNullOrEmpty(plaintext)) return plaintext;

        // Generate a random 96-bit nonce (unique per encryption)
        var nonce = new byte[AesGcm.NonceByteSizes.MaxSize]; // 12 bytes
        RandomNumberGenerator.Fill(nonce);

        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[AesGcm.TagByteSizes.MaxSize]; // 16 bytes

        using var aes = new AesGcm(_masterKey, AesGcm.TagByteSizes.MaxSize);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        // Store as: base64(nonce || tag || ciphertext)
        var combined = new byte[nonce.Length + tag.Length + ciphertext.Length];
        Buffer.BlockCopy(nonce, 0, combined, 0, nonce.Length);
        Buffer.BlockCopy(tag, 0, combined, nonce.Length, tag.Length);
        Buffer.BlockCopy(ciphertext, 0, combined, nonce.Length + tag.Length, ciphertext.Length);

        return Convert.ToBase64String(combined);
    }

    public string Decrypt(string cipherBase64)
    {
        if (string.IsNullOrEmpty(cipherBase64)) return cipherBase64;

        var combined = Convert.FromBase64String(cipherBase64);

        var nonceSize = AesGcm.NonceByteSizes.MaxSize;
        var tagSize = AesGcm.TagByteSizes.MaxSize;

        var nonce = combined[..nonceSize];
        var tag = combined[nonceSize..(nonceSize + tagSize)];
        var ciphertext = combined[(nonceSize + tagSize)..];

        var plaintext = new byte[ciphertext.Length];

        using var aes = new AesGcm(_masterKey, AesGcm.TagByteSizes.MaxSize);
        aes.Decrypt(nonce, ciphertext, tag, plaintext);

        return Encoding.UTF8.GetString(plaintext);
    }
}
```

### Encrypted fields

| Table   | Field              | Reason                           |
|---------|--------------------|----------------------------------|
| users   | first_name         | PII – GDPR Article 4             |
| users   | last_name          | PII – GDPR Article 4             |
| users   | phone_number       | PII – sensitive contact data     |
| users   | national_id        | Sensitive identifier             |
| mfa_devices | secret        | TOTP secret – must be protected  |

### Key management

- Store master key in a secrets manager (HashiCorp Vault, AWS Secrets Manager, Azure Key Vault)
- Rotate keys annually using envelope encryption
- Never commit encryption keys to source control
- Use separate keys per tenant for maximum isolation (envelope encryption pattern)

---

## 9. Session Security

### Session revocation

Sessions can be revoked individually or in bulk. The `user_sessions` table stores the session state:

```sql
-- Revoke a single session
UPDATE user_sessions
SET revoked = TRUE, revoked_at = NOW(), revoke_reason = 'user_logout'
WHERE id = $1 AND tenant_id = current_setting('app.current_tenant_id')::uuid;

-- Revoke all sessions for a user (e.g., after password change)
UPDATE user_sessions
SET revoked = TRUE, revoked_at = NOW(), revoke_reason = 'password_changed'
WHERE user_id = $1 AND tenant_id = $2 AND revoked = FALSE;
```

### Session expiry enforcement

```csharp
// Middleware: validate session is still active on every request
var sessionId = _jwtService.GetSessionId(token);
var session = await _cache.GetOrSetAsync($"session:{sessionId}", async () =>
    await _db.UserSessions.FirstOrDefaultAsync(s =>
        s.Id == sessionId && !s.Revoked && s.ExpiresAt > DateTimeOffset.UtcNow),
    TimeSpan.FromMinutes(1));

if (session == null)
    return Unauthorized("Session has been revoked or expired.");
```

### Device tracking

Track device fingerprints to detect session hijacking:

```csharp
public record DeviceFingerprint(
    string UserAgent,
    string IpAddress,
    string? AcceptLanguage,
    string? AcceptEncoding);

// On each request, compare fingerprint with stored session fingerprint
// Alert if IP changes significantly (different country/ASN)
```

### Session security best practices

- Regenerate session ID after privilege escalation (MFA completion, role change)
- Store refresh tokens as **hashed** values (SHA-256 or bcrypt) in the database
- Implement absolute session timeout (e.g., 8 hours) regardless of activity
- Implement idle session timeout (e.g., 30 minutes of inactivity)
- Log all session creation and revocation events to the audit log

---

## 10. Security Headers

### ASP.NET Core security headers middleware

```csharp
// Program.cs
app.Use(async (context, next) =>
{
    var headers = context.Response.Headers;

    // Prevent clickjacking
    headers["X-Frame-Options"] = "DENY";

    // Prevent MIME type sniffing
    headers["X-Content-Type-Options"] = "nosniff";

    // Enable XSS protection (for legacy browsers)
    headers["X-XSS-Protection"] = "1; mode=block";

    // Enforce HTTPS for 1 year, include subdomains
    headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains; preload";

    // Restrict referrer information
    headers["Referrer-Policy"] = "strict-origin-when-cross-origin";

    // Permissions Policy
    headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()";

    // Content Security Policy
    headers["Content-Security-Policy"] =
        "default-src 'self'; " +
        "script-src 'self'; " +
        "style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' data: https:; " +
        "font-src 'self'; " +
        "connect-src 'self'; " +
        "frame-ancestors 'none'; " +
        "base-uri 'self'; " +
        "form-action 'self'";

    // Remove server information disclosure
    headers.Remove("Server");
    headers.Remove("X-Powered-By");

    await next();
});
```

### HSTS preloading

For production, submit your domain to the [HSTS preload list](https://hstspreload.org):

```csharp
app.UseHsts(); // Configured via Kestrel in production
```

```json
// appsettings.Production.json
{
  "Kestrel": {
    "Endpoints": {
      "Https": {
        "Url": "https://*:443"
      }
    }
  }
}
```

---

## 11. Audit Logging

### What to log

All security-relevant events must be logged with sufficient detail for forensic analysis:

| Event Type                  | Severity | Logged Fields                               |
|-----------------------------|----------|---------------------------------------------|
| `login_success`             | Info     | user_id, ip, user_agent, mfa_used, session_id |
| `login_failure`             | Warning  | email (hashed), ip, user_agent, reason      |
| `logout`                    | Info     | user_id, session_id, all_sessions           |
| `password_changed`          | High     | user_id, ip, triggered_by                  |
| `password_reset_requested`  | Warning  | email (hashed), ip                          |
| `mfa_enrolled`              | High     | user_id, device_id, method                 |
| `mfa_disabled`              | Critical | user_id, ip, admin_override                |
| `account_locked`            | Critical | user_id, reason, locked_until              |
| `account_unlocked`          | High     | user_id, unlocked_by                        |
| `token_refresh`             | Info     | user_id, session_id                         |
| `oauth_token_issued`        | Info     | client_id, user_id, scopes                  |
| `admin_user_modified`       | Critical | admin_id, target_user_id, changes          |
| `data_export_requested`     | High     | user_id, ip                                 |
| `account_deletion_requested`| Critical | user_id, ip, scheduled_at                  |

### Audit log schema

```csharp
public class AuditLog
{
    public Guid Id { get; set; }
    public Guid TenantId { get; set; }
    public Guid? UserId { get; set; }
    public string EventType { get; set; } = default!;
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
    public Dictionary<string, object>? Metadata { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
```

### Audit log immutability

- Audit logs must be append-only; no `UPDATE` or `DELETE` is permitted
- Use a dedicated database user with `INSERT`-only permissions on `audit_logs`
- Forward logs to an external SIEM (Splunk, ELK, Datadog) in real time
- Retain audit logs for a minimum of 12 months (36 months for regulated industries)

---

## 12. Security Incident Response

### Incident severity levels

| Level    | Description                                             | Response Time |
|----------|---------------------------------------------------------|---------------|
| Critical | Active breach, data exfiltration, credential exposure   | 15 minutes    |
| High     | Brute force attack, suspicious mass login attempts      | 1 hour        |
| Medium   | Single account compromise, MFA bypass attempt           | 4 hours       |
| Low      | Policy violation, configuration drift                   | 24 hours      |

### Automated response triggers

```csharp
// SecurityEventService.cs
public async Task HandleBruteForceAsync(string ipAddress, Guid tenantId)
{
    // 1. Immediately rate-limit the IP
    await _rateLimit.BlockIpAsync(ipAddress, TimeSpan.FromHours(1));

    // 2. Create a security event record
    await _db.SecurityEvents.AddAsync(new SecurityEvent
    {
        Id = UuidV7.NewUuid(),
        TenantId = tenantId,
        Type = "brute_force_detected",
        Severity = "high",
        IpAddress = ipAddress,
        Description = "Brute force attack detected from IP",
        CreatedAt = DateTimeOffset.UtcNow
    });

    // 3. Alert the tenant admin
    await _notifications.SendSecurityAlertAsync(tenantId,
        "Brute force attack detected", ipAddress);

    // 4. Write to audit log
    await _audit.LogAsync("security_event_brute_force", null, tenantId,
        new { ipAddress, severity = "high" });
}
```

### Post-incident steps

1. **Contain** – Revoke all active sessions for affected users
2. **Assess** – Review audit logs to determine scope of exposure
3. **Notify** – Follow GDPR 72-hour breach notification requirement if PII was exposed
4. **Remediate** – Rotate secrets, patch vulnerabilities, update WAF rules
5. **Review** – Post-incident review within 5 business days
6. **Document** – Maintain an incident register for regulatory compliance

---

## 13. Dependency Scanning

### Automated vulnerability scanning

```bash
# Check for known vulnerabilities in NuGet packages
dotnet list package --vulnerable --include-transitive

# Audit with the .NET security advisory database
dotnet nuget verify
```

### GitHub Dependabot configuration

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: nuget
    directory: /auth-framework-api
    schedule:
      interval: weekly
    open-pull-requests-limit: 10
    reviewers:
      - security-team
    labels:
      - dependencies
      - security
```

### Recommended scanning tools

| Tool              | Purpose                                    | Integration         |
|-------------------|--------------------------------------------|---------------------|
| Dependabot        | Dependency version updates                 | GitHub native       |
| OWASP Dependency-Check | Known CVE scanning                  | CI/CD pipeline      |
| Snyk              | Code + dependency + container scanning     | GitHub Actions      |
| Trivy             | Container image vulnerability scanning     | Docker build step   |
| SonarCloud        | Code quality + security SAST               | Pull request checks |

### Container scanning

```yaml
# In CI/CD pipeline (see .github/workflows/ci-cd.yml)
- name: Scan container image
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ghcr.io/${{ github.repository }}:${{ github.sha }}
    format: sarif
    exit-code: 1
    severity: CRITICAL,HIGH
```

### Keep these packages up to date

| Package                                     | Reason                                    |
|---------------------------------------------|-------------------------------------------|
| `Microsoft.AspNetCore.Authentication.JwtBearer` | JWT validation vulnerabilities        |
| `BCrypt.Net-Next`                           | Password hashing algorithm updates        |
| `Npgsql.EntityFrameworkCore.PostgreSQL`     | Database driver security patches          |
| `Microsoft.EntityFrameworkCore`             | ORM security patches                      |

---

*Last updated: 2025-01-15 | Framework version: 1.0.0*
