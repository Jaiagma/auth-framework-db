using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>Core user entity representing an identity within a tenant.</summary>
public class User
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Tenant this user belongs to.</summary>
    public Guid TenantId { get; set; }

    /// <summary>User's email address (stored in plaintext for login).</summary>
    public string Email { get; set; } = string.Empty;

    /// <summary>Hashed email for indexed lookups without exposing plaintext.</summary>
    public string EmailHash { get; set; } = string.Empty;

    /// <summary>Current account status.</summary>
    public UserStatus Status { get; set; } = UserStatus.PendingVerification;

    /// <summary>Whether the email address has been verified.</summary>
    public bool IsEmailVerified { get; set; }

    /// <summary>Running count of consecutive failed login attempts.</summary>
    public int FailedLoginAttempts { get; set; }

    /// <summary>Timestamp until which the account is locked.</summary>
    public DateTimeOffset? LockedUntil { get; set; }

    /// <summary>Most recent successful login timestamp.</summary>
    public DateTimeOffset? LastLoginAt { get; set; }

    /// <summary>When the user was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the user was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete timestamp.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    // Navigation properties
    /// <summary>Tenant the user belongs to.</summary>
    public Tenant? Tenant { get; set; }

    /// <summary>User's profile information.</summary>
    public UserProfile? Profile { get; set; }

    /// <summary>User's authentication credentials.</summary>
    public ICollection<UserCredential> Credentials { get; set; } = [];

    /// <summary>Active and historical sessions.</summary>
    public ICollection<UserSession> Sessions { get; set; } = [];

    /// <summary>Registered MFA devices.</summary>
    public ICollection<MfaDevice> MfaDevices { get; set; } = [];

    /// <summary>Audit logs associated with this user.</summary>
    public ICollection<AuditLog> AuditLogs { get; set; } = [];
}
