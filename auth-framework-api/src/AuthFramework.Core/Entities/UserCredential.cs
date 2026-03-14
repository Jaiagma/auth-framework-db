using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>Stores authentication credentials for a user.</summary>
public class UserCredential
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User this credential belongs to.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Type of credential stored.</summary>
    public CredentialType CredentialType { get; set; }

    /// <summary>BCrypt-hashed password (only set for Password credentials).</summary>
    public string? PasswordHash { get; set; }

    /// <summary>When the credential was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the credential was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
