namespace AuthFramework.Core.Entities;

/// <summary>A one-time MFA recovery code for account recovery when primary MFA is unavailable.</summary>
public class MfaRecoveryCode
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User this code belongs to.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>SHA-256 hash of the recovery code.</summary>
    public string CodeHash { get; set; } = string.Empty;

    /// <summary>When the code was used (null if still valid).</summary>
    public DateTimeOffset? UsedAt { get; set; }

    /// <summary>When the code was generated.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
