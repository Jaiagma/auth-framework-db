namespace AuthFramework.Core.Entities;

/// <summary>A secure token sent via email to verify ownership of an address.</summary>
public class EmailVerificationToken
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User this token was issued for.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>SHA-256 hash of the verification token.</summary>
    public string TokenHash { get; set; } = string.Empty;

    /// <summary>The email address being verified.</summary>
    public string Email { get; set; } = string.Empty;

    /// <summary>When this token expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>When this token was used (null if unused).</summary>
    public DateTimeOffset? UsedAt { get; set; }

    /// <summary>When the token was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
