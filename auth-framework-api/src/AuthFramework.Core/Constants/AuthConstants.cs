namespace AuthFramework.Core.Constants;

/// <summary>Application-wide authentication and token constants.</summary>
public static class AuthConstants
{
    /// <summary>JWT token issuer claim name.</summary>
    public const string Issuer = "AuthFramework";

    /// <summary>Default access token lifetime in minutes.</summary>
    public const int DefaultAccessTokenExpiryMinutes = 15;

    /// <summary>Default refresh token lifetime in days.</summary>
    public const int DefaultRefreshTokenExpiryDays = 30;

    /// <summary>Default password reset token lifetime in minutes.</summary>
    public const int PasswordResetTokenExpiryMinutes = 60;

    /// <summary>Default email verification token lifetime in hours.</summary>
    public const int EmailVerificationTokenExpiryHours = 24;

    /// <summary>Maximum failed login attempts before account lock.</summary>
    public const int MaxFailedLoginAttempts = 5;

    /// <summary>Account lock duration in minutes after exceeding failed attempts.</summary>
    public const int AccountLockDurationMinutes = 15;

    /// <summary>Default MFA challenge expiry in minutes.</summary>
    public const int MfaChallengeExpiryMinutes = 10;

    /// <summary>Number of TOTP recovery codes to generate.</summary>
    public const int RecoveryCodeCount = 10;

    /// <summary>JWT claim key for tenant ID.</summary>
    public const string TenantIdClaim = "tid";

    /// <summary>JWT claim key for user ID.</summary>
    public const string UserIdClaim = "uid";

    /// <summary>JWT claim key for session ID.</summary>
    public const string SessionIdClaim = "sid";

    /// <summary>HTTP header name for tenant identification.</summary>
    public const string TenantHeader = "X-Tenant-ID";

    /// <summary>HTTP header name for correlation ID tracing.</summary>
    public const string CorrelationIdHeader = "X-Correlation-ID";

    /// <summary>Minimum password length.</summary>
    public const int MinPasswordLength = 8;

    /// <summary>Maximum password length.</summary>
    public const int MaxPasswordLength = 128;

    /// <summary>BCrypt work factor for password hashing.</summary>
    public const int BcryptWorkFactor = 12;
}
