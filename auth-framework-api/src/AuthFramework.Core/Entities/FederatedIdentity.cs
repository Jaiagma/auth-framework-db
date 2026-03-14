using System.Text.Json;

namespace AuthFramework.Core.Entities;

/// <summary>Links a local user account to an external identity at an identity provider.</summary>
public class FederatedIdentity
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Local user account.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Identity provider this identity comes from.</summary>
    public Guid ProviderId { get; set; }

    /// <summary>The user's ID at the external provider.</summary>
    public string ExternalUserId { get; set; } = string.Empty;

    /// <summary>The user's email at the external provider.</summary>
    public string? ExternalEmail { get; set; }

    /// <summary>Additional claims/attributes from the provider stored as JSONB.</summary>
    public JsonDocument? Attributes { get; set; }

    /// <summary>When the link was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the link was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>Local user.</summary>
    public User? User { get; set; }

    /// <summary>Identity provider.</summary>
    public IdentityProvider? Provider { get; set; }
}
