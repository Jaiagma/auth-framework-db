using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>An external identity provider configured for SSO.</summary>
public class IdentityProvider
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Tenant this provider belongs to.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Friendly name shown in the UI.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>Protocol/provider type.</summary>
    public ProviderType ProviderType { get; set; }

    /// <summary>OAuth/OIDC client ID for this provider.</summary>
    public string? ClientId { get; set; }

    /// <summary>Whether this provider is active and available.</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>OIDC discovery or SAML metadata URL.</summary>
    public string? MetadataUrl { get; set; }

    /// <summary>When the provider was configured.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the provider was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>Federated identities linked through this provider.</summary>
    public ICollection<FederatedIdentity> FederatedIdentities { get; set; } = [];
}
