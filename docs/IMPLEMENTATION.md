# Implementation Guide – .NET 9 + PostgreSQL 16

This guide walks through setting up, configuring, and running the multi-tenant authentication framework from scratch.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Project Setup](#project-setup)
3. [Database Setup](#database-setup)
4. [Configuration](#configuration)
5. [Running Migrations with EF Core](#running-migrations-with-ef-core)
6. [Starting the Application](#starting-the-application)
7. [Authentication Flow Walkthrough](#authentication-flow-walkthrough)
8. [MFA Implementation Guide](#mfa-implementation-guide)
9. [OAuth 2.0 Flow Guide](#oauth-20-flow-guide)
10. [SSO Integration Guide](#sso-integration-guide)
11. [Tenant Isolation Explanation](#tenant-isolation-explanation)
12. [UUID v7 Usage Guide](#uuid-v7-usage-guide)

---

## 1. Prerequisites

| Tool             | Minimum Version | Notes                                       |
|------------------|-----------------|---------------------------------------------|
| .NET SDK         | 9.0             | <https://dotnet.microsoft.com/download>     |
| PostgreSQL       | 16+             | With `pgcrypto`, `uuid-ossp`, `pg_trgm`     |
| Docker           | 24+             | Optional, used for local Postgres            |
| Docker Compose   | 2.20+           | Optional, used for full local stack          |
| Git              | 2.40+           | Source control                               |
| OpenSSL          | 3.x             | For generating RSA key pairs                 |

### Install .NET 9 SDK

```bash
# macOS (Homebrew)
brew install dotnet@9

# Ubuntu / Debian
wget https://dot.net/v1/dotnet-install.sh
chmod +x dotnet-install.sh
./dotnet-install.sh --channel 9.0

# Windows
winget install Microsoft.DotNet.SDK.9
```

Verify: `dotnet --version` → `9.0.x`

### Install PostgreSQL 16 via Docker (recommended for local dev)

```bash
docker run -d \
  --name auth-postgres \
  -e POSTGRES_USER=authuser \
  -e POSTGRES_PASSWORD=authpassword \
  -e POSTGRES_DB=authdb \
  -p 5432:5432 \
  postgres:16-alpine
```

---

## 2. Project Setup

### Clone the repository

```bash
git clone https://github.com/your-org/auth-framework-db.git
cd auth-framework-db
```

### Recommended solution structure

```
auth-framework-db/
├── auth-framework-api/            # .NET 9 Web API project
│   ├── Controllers/
│   │   ├── AuthController.cs
│   │   ├── MfaController.cs
│   │   ├── OAuthController.cs
│   │   ├── SsoController.cs
│   │   ├── UsersController.cs
│   │   └── AdminController.cs
│   ├── Data/
│   │   ├── AppDbContext.cs        # EF Core DbContext with RLS
│   │   ├── Entities/              # Entity classes
│   │   └── Migrations/            # EF Core migrations
│   ├── Services/
│   │   ├── AuthService.cs
│   │   ├── TokenService.cs
│   │   ├── MfaService.cs
│   │   ├── OAuthService.cs
│   │   ├── SsoService.cs
│   │   └── EncryptionService.cs
│   ├── Middleware/
│   │   ├── TenantMiddleware.cs
│   │   └── RateLimitMiddleware.cs
│   ├── appsettings.json
│   ├── appsettings.Development.json
│   └── Program.cs
├── docs/
├── samples/
├── migrations/                    # Raw SQL migration scripts
├── schema.sql
├── functions.sql
├── triggers.sql
├── indexes.sql
├── rls_policies.sql
├── seed_data.sql
├── docker-compose.yml
└── .github/
    └── workflows/
        └── ci-cd.yml
```

### Create the .NET solution and project

```bash
dotnet new sln -n AuthFramework
dotnet new webapi -n AuthFramework.Api --framework net9.0 -o auth-framework-api
dotnet sln add auth-framework-api/AuthFramework.Api.csproj
```

### Add required NuGet packages

```bash
cd auth-framework-api

# EF Core + PostgreSQL
dotnet add package Microsoft.EntityFrameworkCore --version 9.0.0
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL --version 9.0.0

# JWT authentication
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer --version 9.0.0

# TOTP / MFA
dotnet add package Otp.NET --version 1.4.0

# BCrypt password hashing
dotnet add package BCrypt.Net-Next --version 4.0.3

# Rate limiting
dotnet add package AspNetCoreRateLimit --version 5.0.0

# Data protection (AES encryption)
dotnet add package Microsoft.AspNetCore.DataProtection --version 9.0.0

# OpenTelemetry (optional, for observability)
dotnet add package OpenTelemetry.Extensions.Hosting --version 1.10.0
```

---

## 3. Database Setup

Run the SQL scripts in order against your PostgreSQL instance:

```bash
export PGHOST=localhost
export PGPORT=5432
export PGUSER=authuser
export PGPASSWORD=authpassword
export PGDATABASE=authdb
```

### Step 1 – Enable extensions

```bash
psql -f extensions.sql
```

`extensions.sql` enables:
- `pgcrypto` – cryptographic functions (`gen_random_bytes`, `crypt`)
- `uuid-ossp` – `uuid_generate_v4()` for legacy compatibility
- `pg_trgm` – trigram indexes for fuzzy search on emails/names

### Step 2 – Create enumerations

```bash
psql -f enums.sql
```

Creates custom Postgres `ENUM` types used throughout the schema (e.g., `user_status`, `mfa_method`, `oauth_grant_type`, `audit_event_type`).

### Step 3 – Create schema (tables)

```bash
psql -f schema.sql
```

Creates all tables including: `tenants`, `users`, `user_sessions`, `mfa_devices`, `oauth_applications`, `oauth_tokens`, `sso_providers`, `audit_logs`, `security_events`, `user_consents`, `data_deletion_requests`, `data_retention_policies`.

### Step 4 – Create stored functions

```bash
psql -f functions.sql
```

Key functions:
- `generate_uuid_v7()` – generates UUID v7 values
- `hash_token(token TEXT)` – SHA-256 hashes tokens for secure storage
- `cleanup_expired_sessions()` – removes expired session records
- `enforce_tenant_isolation(tenant_id UUID)` – sets the RLS context variable

### Step 5 – Create triggers

```bash
psql -f triggers.sql
```

Triggers include:
- `update_updated_at` – auto-updates `updated_at` timestamps on every table
- `audit_user_changes` – writes to `audit_logs` on user record mutations
- `lock_account_on_failures` – locks account after N consecutive failed logins
- `enforce_password_history` – prevents reuse of last N passwords

### Step 6 – Create indexes

```bash
psql -f indexes.sql
```

Performance indexes on high-query columns: `users(email, tenant_id)`, `user_sessions(user_id, expires_at)`, `audit_logs(tenant_id, created_at)`, trigram indexes for search.

### Step 7 – Enable Row Level Security

```bash
psql -f rls_policies.sql
```

RLS policies ensure every query is scoped to the current tenant. The application sets `SET LOCAL app.current_tenant_id = '<uuid>'` at the start of each request.

### Step 8 – Seed initial data

```bash
psql -f seed_data.sql
```

Creates a default `system` tenant, `super_admin` role, and default data retention policies.

### Verify the setup

```bash
psql -c "\dt public.*" | head -30
psql -c "SELECT COUNT(*) FROM tenants;"
```

---

## 4. Configuration

### appsettings.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=authdb;Username=authuser;Password=authpassword;Include Error Detail=true"
  },
  "Jwt": {
    "Issuer": "https://auth.example.com",
    "Audience": "https://api.example.com",
    "AccessTokenExpiryMinutes": 15,
    "RefreshTokenExpiryDays": 30,
    "Algorithm": "RS256",
    "PrivateKeyPath": "/run/secrets/jwt_private_key.pem",
    "PublicKeyPath": "/run/secrets/jwt_public_key.pem"
  },
  "Encryption": {
    "MasterKeyBase64": "REPLACE_WITH_32_BYTE_BASE64_KEY",
    "Algorithm": "AES-256-GCM"
  },
  "RateLimit": {
    "LoginAttemptsPerMinute": 10,
    "PasswordResetPerHour": 5,
    "GeneralRequestsPerMinute": 300
  },
  "Email": {
    "Provider": "smtp",
    "SmtpHost": "smtp.example.com",
    "SmtpPort": 587,
    "FromAddress": "noreply@example.com",
    "FromName": "Auth Framework"
  },
  "DataProtection": {
    "KeyStoragePath": "/var/app/dataprotection-keys",
    "ApplicationName": "AuthFramework"
  },
  "AllowedHosts": "*",
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning",
      "Microsoft.EntityFrameworkCore.Database.Command": "Warning"
    }
  }
}
```

### appsettings.Development.json

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=authdb;Username=authuser;Password=authpassword"
  },
  "Jwt": {
    "Algorithm": "HS256",
    "SecretKey": "dev-only-secret-key-minimum-32-chars!!"
  },
  "Logging": {
    "LogLevel": {
      "Default": "Debug",
      "Microsoft.EntityFrameworkCore.Database.Command": "Information"
    }
  }
}
```

### Generate RSA keys for production JWT (RS256)

```bash
# Generate 4096-bit RSA private key
openssl genrsa -out jwt_private_key.pem 4096

# Extract public key
openssl rsa -in jwt_private_key.pem -pubout -out jwt_public_key.pem

# Store as Docker/Kubernetes secrets, never commit to source control
```

### Generate AES-256 encryption key

```bash
# Generate a 32-byte random key, base64-encoded
openssl rand -base64 32
# Store the output as Encryption:MasterKeyBase64
```

---

## 5. Running Migrations with EF Core

### Install the EF Core CLI tools

```bash
dotnet tool install --global dotnet-ef
dotnet tool update --global dotnet-ef
```

### AppDbContext setup

```csharp
// Data/AppDbContext.cs
public class AppDbContext : DbContext
{
    private readonly IHttpContextAccessor _httpContextAccessor;

    public AppDbContext(DbContextOptions<AppDbContext> options,
        IHttpContextAccessor httpContextAccessor) : base(options)
    {
        _httpContextAccessor = httpContextAccessor;
    }

    public DbSet<Tenant> Tenants => Set<Tenant>();
    public DbSet<User> Users => Set<User>();
    public DbSet<UserSession> UserSessions => Set<UserSession>();
    public DbSet<MfaDevice> MfaDevices => Set<MfaDevice>();
    public DbSet<AuditLog> AuditLogs => Set<AuditLog>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Global query filter for tenant isolation
        var tenantId = GetCurrentTenantId();
        modelBuilder.Entity<User>()
            .HasQueryFilter(u => u.TenantId == tenantId);
        modelBuilder.Entity<UserSession>()
            .HasQueryFilter(s => s.TenantId == tenantId);
        // ... apply to all tenant-scoped entities
    }

    public override async Task<int> SaveChangesAsync(CancellationToken ct = default)
    {
        await SetTenantContextAsync();
        return await base.SaveChangesAsync(ct);
    }

    private async Task SetTenantContextAsync()
    {
        var tenantId = GetCurrentTenantId();
        if (tenantId != Guid.Empty)
        {
            // Set RLS context for the current transaction
            await Database.ExecuteSqlRawAsync(
                $"SET LOCAL app.current_tenant_id = '{tenantId}'");
        }
    }

    private Guid GetCurrentTenantId()
    {
        var tenantIdStr = _httpContextAccessor.HttpContext?
            .Items["TenantId"]?.ToString();
        return Guid.TryParse(tenantIdStr, out var id) ? id : Guid.Empty;
    }
}
```

### Create and apply migrations

```bash
cd auth-framework-api

# Create the initial migration
dotnet ef migrations add InitialCreate \
  --output-dir Data/Migrations \
  --context AppDbContext

# Apply to development database
dotnet ef database update

# Apply to a specific connection string
dotnet ef database update \
  --connection "Host=prod-db;Database=authdb;Username=authuser;Password=secret"
```

### Using raw SQL migrations instead of EF migrations

If you prefer the provided raw SQL scripts over EF Core code-first migrations:

```bash
# Run all scripts in order
for script in extensions.sql enums.sql schema.sql functions.sql \
              triggers.sql indexes.sql rls_policies.sql seed_data.sql; do
    echo "Running $script..."
    psql -f "$script"
done
```

Then configure EF Core to use an existing database:

```csharp
// In Program.cs, skip automatic migration
// Use Database.EnsureCreated() only in development
if (app.Environment.IsDevelopment())
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    // Schema already managed by SQL scripts; just verify connectivity
    await db.Database.CanConnectAsync();
}
```

---

## 6. Starting the Application

### Configure and run

```bash
cd auth-framework-api

# Set development environment
export ASPNETCORE_ENVIRONMENT=Development

# Run with hot reload
dotnet watch run

# Or run normally
dotnet run

# Application starts on:
# http://localhost:5000
# https://localhost:5001
```

### Using Docker Compose (recommended)

```bash
# From the repo root
docker compose up --build

# Services:
# API:      http://localhost:5000
# Postgres: localhost:5432
# Adminer:  http://localhost:8080
```

### Verify the API is running

```bash
curl http://localhost:5000/health
# {"status":"healthy","database":"connected","version":"1.0.0"}
```

---

## 7. Authentication Flow Walkthrough

### Program.cs setup

```csharp
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using System.Text;

var builder = WebApplication.CreateBuilder(args);

// Database
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

// HTTP context for tenant resolution
builder.Services.AddHttpContextAccessor();

// JWT Authentication
var jwtConfig = builder.Configuration.GetSection("Jwt");
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ValidIssuer = jwtConfig["Issuer"],
            ValidAudience = jwtConfig["Audience"],
            IssuerSigningKey = new SymmetricSecurityKey(
                Encoding.UTF8.GetBytes(jwtConfig["SecretKey"]!)),
            ClockSkew = TimeSpan.FromSeconds(30)
        };
    });

builder.Services.AddAuthorization();

// Application services
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<ITokenService, TokenService>();
builder.Services.AddScoped<IMfaService, MfaService>();
builder.Services.AddScoped<IEncryptionService, EncryptionService>();

var app = builder.Build();

// Middleware pipeline order matters
app.UseHttpsRedirection();
app.UseMiddleware<TenantMiddleware>();   // Resolve X-Tenant-ID first
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();

app.Run();
```

### TenantMiddleware

```csharp
// Middleware/TenantMiddleware.cs
public class TenantMiddleware
{
    private readonly RequestDelegate _next;

    public TenantMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context, AppDbContext db)
    {
        if (!context.Request.Headers.TryGetValue("X-Tenant-ID", out var tenantIdStr)
            || !Guid.TryParse(tenantIdStr, out var tenantId))
        {
            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new
            {
                error = "validation_error",
                message = "X-Tenant-ID header is required and must be a valid UUID."
            });
            return;
        }

        // Validate tenant exists and is active
        var tenant = await db.Tenants
            .AsNoTracking()
            .FirstOrDefaultAsync(t => t.Id == tenantId && t.Status == TenantStatus.Active);

        if (tenant == null)
        {
            context.Response.StatusCode = 404;
            await context.Response.WriteAsJsonAsync(new
            {
                error = "not_found",
                message = "Tenant not found or inactive."
            });
            return;
        }

        context.Items["TenantId"] = tenantId.ToString();
        context.Items["Tenant"] = tenant;

        await _next(context);
    }
}
```

### AuthService – Register and Login

```csharp
// Services/AuthService.cs
public class AuthService : IAuthService
{
    private readonly AppDbContext _db;
    private readonly ITokenService _tokenService;
    private readonly IEncryptionService _encryption;

    public AuthService(AppDbContext db, ITokenService tokenService,
        IEncryptionService encryption)
    {
        _db = db;
        _tokenService = tokenService;
        _encryption = encryption;
    }

    public async Task<RegisterResult> RegisterAsync(RegisterRequest request, Guid tenantId)
    {
        // Check for duplicate email within the tenant
        var exists = await _db.Users.AnyAsync(u =>
            u.TenantId == tenantId && u.Email == request.Email.ToLowerInvariant());

        if (exists)
            throw new ConflictException("conflict", "An account with this email already exists.");

        var userId = UuidV7.NewUuid();

        var user = new User
        {
            Id = userId,
            TenantId = tenantId,
            Email = request.Email.ToLowerInvariant(),
            // Encrypt PII at rest using AES-256-GCM
            FirstNameEncrypted = _encryption.Encrypt(request.FirstName),
            LastNameEncrypted = _encryption.Encrypt(request.LastName),
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password, workFactor: 12),
            EmailVerified = false,
            Status = UserStatus.PendingVerification,
            CreatedAt = DateTimeOffset.UtcNow
        };

        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        // Send verification email (fire-and-forget with proper error handling)
        await SendVerificationEmailAsync(user);

        return new RegisterResult { UserId = userId, EmailVerificationRequired = true };
    }

    public async Task<LoginResult> LoginAsync(LoginRequest request, Guid tenantId)
    {
        var user = await _db.Users
            .FirstOrDefaultAsync(u => u.TenantId == tenantId
                && u.Email == request.Email.ToLowerInvariant());

        // Use constant-time comparison to prevent user enumeration timing attacks
        var passwordValid = user != null &&
            BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash);

        if (user == null || !passwordValid)
        {
            if (user != null)
                await RecordFailedLoginAsync(user);

            throw new UnauthorizedException("credentials_invalid", "Invalid email or password.");
        }

        if (user.Status == UserStatus.Locked)
            throw new ForbiddenException("account_locked", "Account is locked.");

        if (!user.EmailVerified)
            throw new ForbiddenException("email_not_verified", "Please verify your email.");

        // Check if MFA is enrolled and required
        var hasMfa = await _db.MfaDevices.AnyAsync(d =>
            d.UserId == user.Id && d.IsActive);

        if (hasMfa)
        {
            var mfaToken = _tokenService.GenerateMfaToken(user.Id, tenantId);
            return new LoginResult { MfaRequired = true, MfaToken = mfaToken };
        }

        return await CreateSessionAsync(user, tenantId, request.DeviceName);
    }

    private async Task<LoginResult> CreateSessionAsync(User user, Guid tenantId, string? deviceName)
    {
        var sessionId = UuidV7.NewUuid();
        var session = new UserSession
        {
            Id = sessionId,
            UserId = user.Id,
            TenantId = tenantId,
            DeviceName = deviceName,
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(15)
        };

        _db.UserSessions.Add(session);
        await _db.SaveChangesAsync();

        var accessToken = _tokenService.GenerateAccessToken(user, tenantId, sessionId);
        var refreshToken = _tokenService.GenerateRefreshToken();

        // Store hashed refresh token
        session.RefreshTokenHash = _tokenService.HashToken(refreshToken);
        session.RefreshTokenExpiresAt = DateTimeOffset.UtcNow.AddDays(30);
        await _db.SaveChangesAsync();

        return new LoginResult
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = 900,
            SessionId = sessionId
        };
    }
}
```

---

## 8. MFA Implementation Guide

### TOTP enrollment with OTP.NET

```csharp
// Services/MfaService.cs
using OtpNet;

public class MfaService : IMfaService
{
    private readonly AppDbContext _db;
    private readonly IEncryptionService _encryption;

    public MfaService(AppDbContext db, IEncryptionService encryption)
    {
        _db = db;
        _encryption = encryption;
    }

    public async Task<EnrollResult> EnrollTotpAsync(Guid userId, Guid tenantId, string deviceName)
    {
        // Generate a cryptographically random 20-byte secret
        var secretBytes = KeyGeneration.GenerateRandomKey(20);
        var secretBase32 = Base32Encoding.ToString(secretBytes);

        var enrollmentId = UuidV7.NewUuid();

        // Generate backup codes
        var backupCodes = Enumerable.Range(0, 8)
            .Select(_ => GenerateBackupCode())
            .ToList();

        var device = new MfaDevice
        {
            Id = enrollmentId,
            UserId = userId,
            TenantId = tenantId,
            Method = MfaMethod.Totp,
            DeviceName = deviceName,
            // Encrypt the TOTP secret at rest
            SecretEncrypted = _encryption.Encrypt(secretBase32),
            BackupCodeHashes = backupCodes
                .Select(c => BCrypt.Net.BCrypt.HashPassword(c, 4))
                .ToList(),
            IsActive = false, // Not active until verified
            CreatedAt = DateTimeOffset.UtcNow
        };

        _db.MfaDevices.Add(device);
        await _db.SaveChangesAsync();

        // Build the otpauth:// URI for QR code generation
        var user = await _db.Users.FindAsync(userId);
        var issuer = "AuthFramework";
        var label = Uri.EscapeDataString($"{issuer}:{user!.Email}");
        var qrUri = $"otpauth://totp/{label}?secret={secretBase32}&issuer={Uri.EscapeDataString(issuer)}&algorithm=SHA1&digits=6&period=30";

        return new EnrollResult
        {
            EnrollmentId = enrollmentId,
            Secret = secretBase32,
            QrCodeUri = qrUri,
            BackupCodes = backupCodes
        };
    }

    public async Task<bool> VerifyTotpAsync(Guid enrollmentId, string code)
    {
        var device = await _db.MfaDevices.FindAsync(enrollmentId)
            ?? throw new NotFoundException("not_found", "MFA device not found.");

        var secret = _encryption.Decrypt(device.SecretEncrypted);
        var secretBytes = Base32Encoding.ToBytes(secret);

        var totp = new Totp(secretBytes, step: 30, totpSize: 6);

        // Allow ±1 time step to handle clock skew
        var isValid = totp.VerifyTotp(code, out _, new VerificationWindow(1, 1));

        if (isValid)
        {
            device.IsActive = true;
            device.LastUsedAt = DateTimeOffset.UtcNow;
            await _db.SaveChangesAsync();
        }

        return isValid;
    }

    private static string GenerateBackupCode()
    {
        var bytes = new byte[5];
        System.Security.Cryptography.RandomNumberGenerator.Fill(bytes);
        var code = Convert.ToHexString(bytes);
        return $"{code[..4]}-{code[4..]}";
    }
}
```

---

## 9. OAuth 2.0 Flow Guide

### Authorization Code flow with PKCE

```csharp
// Services/OAuthService.cs
public class OAuthService : IOAuthService
{
    public async Task<AuthorizeResult> AuthorizeAsync(AuthorizeRequest request)
    {
        // Validate client
        var client = await _db.OAuthApplications
            .FirstOrDefaultAsync(a => a.ClientId == request.ClientId)
            ?? throw new BadRequestException("invalid_client", "Unknown client_id.");

        // Validate redirect URI (exact match required)
        if (!client.RedirectUris.Contains(request.RedirectUri))
            throw new BadRequestException("invalid_request", "redirect_uri mismatch.");

        // Validate PKCE
        if (string.IsNullOrEmpty(request.CodeChallenge) || request.CodeChallengeMethod != "S256")
            throw new BadRequestException("invalid_request", "PKCE with S256 is required.");

        // Store the authorization code
        var code = GenerateSecureCode();
        var authCode = new OAuthAuthorizationCode
        {
            Id = UuidV7.NewUuid(),
            Code = HashToken(code),
            ClientId = client.Id,
            UserId = _currentUser.Id,
            RedirectUri = request.RedirectUri,
            Scopes = request.Scope.Split(' '),
            CodeChallenge = request.CodeChallenge,
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(10)
        };

        _db.OAuthAuthorizationCodes.Add(authCode);
        await _db.SaveChangesAsync();

        return new AuthorizeResult { Code = code, State = request.State };
    }

    public async Task<TokenResponse> ExchangeCodeAsync(TokenRequest request)
    {
        var codeHash = HashToken(request.Code);
        var authCode = await _db.OAuthAuthorizationCodes
            .Include(c => c.Client)
            .FirstOrDefaultAsync(c => c.Code == codeHash && c.ExpiresAt > DateTimeOffset.UtcNow)
            ?? throw new BadRequestException("invalid_grant", "Authorization code is invalid or expired.");

        // Validate PKCE verifier against stored challenge
        var challengeBytes = SHA256.HashData(Encoding.ASCII.GetBytes(request.CodeVerifier));
        var computedChallenge = Base64UrlEncoder.Encode(challengeBytes);

        if (computedChallenge != authCode.CodeChallenge)
            throw new BadRequestException("invalid_grant", "Code verifier does not match challenge.");

        // Delete used code (one-time use)
        _db.OAuthAuthorizationCodes.Remove(authCode);

        var user = await _db.Users.FindAsync(authCode.UserId);
        var accessToken = _tokenService.GenerateOAuthAccessToken(user!, authCode.Client, authCode.Scopes);
        var refreshToken = _tokenService.GenerateRefreshToken();

        await _db.SaveChangesAsync();

        return new TokenResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            TokenType = "Bearer",
            ExpiresIn = 900,
            Scope = string.Join(" ", authCode.Scopes)
        };
    }
}
```

---

## 10. SSO Integration Guide

### OIDC provider configuration

```csharp
// Program.cs – add OIDC authentication handler
builder.Services.AddAuthentication()
    .AddOpenIdConnect("google", options =>
    {
        options.Authority = "https://accounts.google.com";
        options.ClientId = builder.Configuration["Sso:Google:ClientId"]!;
        options.ClientSecret = builder.Configuration["Sso:Google:ClientSecret"]!;
        options.ResponseType = "code";
        options.Scope.Add("openid");
        options.Scope.Add("profile");
        options.Scope.Add("email");
        options.CallbackPath = "/api/sso/callback/google";
        options.SaveTokens = false; // We manage our own sessions
    });
```

### SAML provider (using ITfoxtec.Identity.Saml2)

```bash
dotnet add package ITfoxtec.Identity.Saml2 --version 4.8.0
dotnet add package ITfoxtec.Identity.Saml2.MvcCore --version 4.8.0
```

```csharp
// Configure SAML in Program.cs
builder.Services.Configure<Saml2Configuration>(saml2Config =>
{
    saml2Config.Issuer = "https://auth.example.com";
    saml2Config.AllowedAudienceUris.Add("https://auth.example.com");
    var entityDescriptor = new EntityDescriptor();
    entityDescriptor.ReadIdPSsoDescriptorFromUrl(
        new Uri("https://idp.example.com/metadata"));
    saml2Config.SingleSignOnDestination = entityDescriptor
        .IdPSsoDescriptor.SingleSignOnServices.First().Location;
    saml2Config.SignatureValidationCertificates.Add(
        entityDescriptor.IdPSsoDescriptor.SigningCertificates.First());
});
```

### JIT (Just-in-Time) user provisioning

```csharp
public async Task<User> ProvisionOrUpdateSsoUserAsync(
    SsoProvider provider, ClaimsPrincipal externalPrincipal, Guid tenantId)
{
    var externalId = externalPrincipal.FindFirstValue(ClaimTypes.NameIdentifier)!;
    var email = externalPrincipal.FindFirstValue(ClaimTypes.Email)!;

    // Find existing user by external ID or email
    var user = await _db.Users
        .FirstOrDefaultAsync(u => u.TenantId == tenantId
            && (u.SsoProviderId == provider.Id && u.ExternalId == externalId
                || u.Email == email.ToLowerInvariant()));

    if (user == null)
    {
        // JIT provision a new user
        user = new User
        {
            Id = UuidV7.NewUuid(),
            TenantId = tenantId,
            Email = email.ToLowerInvariant(),
            FirstNameEncrypted = _encryption.Encrypt(
                externalPrincipal.FindFirstValue(ClaimTypes.GivenName) ?? ""),
            LastNameEncrypted = _encryption.Encrypt(
                externalPrincipal.FindFirstValue(ClaimTypes.Surname) ?? ""),
            EmailVerified = true, // Trusted from IdP
            SsoProviderId = provider.Id,
            ExternalId = externalId,
            Status = UserStatus.Active,
            CreatedAt = DateTimeOffset.UtcNow
        };
        _db.Users.Add(user);
    }
    else
    {
        // Update last login
        user.LastLoginAt = DateTimeOffset.UtcNow;
    }

    await _db.SaveChangesAsync();
    return user;
}
```

---

## 11. Tenant Isolation Explanation

Tenant isolation is enforced at multiple layers:

### Layer 1 – Middleware (HTTP layer)

Every request must provide a valid `X-Tenant-ID` header. The `TenantMiddleware` validates the tenant exists and is active before any controller logic runs.

### Layer 2 – EF Core Global Query Filters (ORM layer)

Global query filters automatically append `WHERE tenant_id = @currentTenantId` to every LINQ query, preventing cross-tenant data leaks even if application code forgets to filter:

```csharp
modelBuilder.Entity<User>()
    .HasQueryFilter(u => u.TenantId == _currentTenantId);
```

### Layer 3 – PostgreSQL Row Level Security (database layer)

RLS policies are the last line of defense. Even if the application connects directly to the database (e.g., for reporting), only rows belonging to the set tenant context are visible:

```sql
-- In rls_policies.sql
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON users
    USING (tenant_id = current_setting('app.current_tenant_id')::uuid);
```

The application sets this at the start of each transaction:

```csharp
await Database.ExecuteSqlRawAsync(
    $"SET LOCAL app.current_tenant_id = '{tenantId}'");
```

### Layer 4 – JWT claims validation

The JWT access token contains the `tenant_id` claim. Middleware validates the token's `tenant_id` matches the `X-Tenant-ID` header on every request.

---

## 12. UUID v7 Usage Guide

UUID v7 provides time-ordered UUIDs that are sortable and index-friendly in PostgreSQL.

### Why UUID v7?

- **Monotonically increasing** – new rows insert at the end of B-tree indexes, avoiding page splits
- **Time-embedded** – the first 48 bits encode millisecond Unix time, enabling efficient range queries
- **Globally unique** – no coordination needed across services
- **Drop-in UUID replacement** – fully compatible with `uuid` column types

### .NET implementation

```csharp
// Helpers/UuidV7.cs
public static class UuidV7
{
    public static Guid NewUuid()
    {
        // .NET 9 natively supports UUID v7
        return Guid.CreateVersion7();
    }

    public static DateTimeOffset GetTimestamp(Guid uuidV7)
    {
        var bytes = uuidV7.ToByteArray();
        // UUID v7: first 6 bytes are Unix timestamp in milliseconds
        var ms = ((long)bytes[0] << 40)
               | ((long)bytes[1] << 32)
               | ((long)bytes[2] << 24)
               | ((long)bytes[3] << 16)
               | ((long)bytes[4] << 8)
               | bytes[5];
        return DateTimeOffset.FromUnixTimeMilliseconds(ms);
    }
}
```

### PostgreSQL function (in functions.sql)

```sql
CREATE OR REPLACE FUNCTION generate_uuid_v7()
RETURNS UUID AS $$
DECLARE
    unix_ms BIGINT;
    rand_bytes BYTEA;
    uuid_bytes BYTEA;
BEGIN
    unix_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
    rand_bytes := gen_random_bytes(10);

    uuid_bytes := SET_BYTE(
        SET_BYTE(
            SET_BYTE(
                decode(lpad(to_hex(unix_ms), 12, '0'), 'hex') || rand_bytes,
                6, (GET_BYTE(rand_bytes, 0) & 15) | 112  -- Version 7
            ),
            8, (GET_BYTE(rand_bytes, 2) & 63) | 128       -- Variant bits
        ),
        0, 0
    );

    RETURN encode(uuid_bytes, 'hex')::UUID;
END;
$$ LANGUAGE plpgsql;
```

### Using UUID v7 as default primary key

```csharp
// In entity configuration
modelBuilder.Entity<User>(entity =>
{
    entity.Property(u => u.Id)
        .HasDefaultValueSql("generate_uuid_v7()")
        .ValueGeneratedOnAdd();
});
```

---

*Last updated: 2025-01-15 | Framework version: 1.0.0*
