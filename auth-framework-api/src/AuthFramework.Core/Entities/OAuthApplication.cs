using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>An OAuth 2.0 client application registered under a tenant.</summary>
public class OAuthApplication
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Tenant that owns this application.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Human-readable application name.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>OAuth 2.0 client_id (publicly shareable).</summary>
    public string ClientId { get; set; } = string.Empty;

    /// <summary>BCrypt hash of the client secret.</summary>
    public string? ClientSecretHash { get; set; }

    /// <summary>Type of OAuth application.</summary>
    public ApplicationType ApplicationType { get; set; }

    /// <summary>Allowed redirect URIs for authorization code flow.</summary>
    public string[] RedirectUris { get; set; } = [];

    /// <summary>Scopes this application is permitted to request.</summary>
    public string[] AllowedScopes { get; set; } = [];

    /// <summary>Whether the application is active.</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>When the application was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the application was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>OAuth tokens issued to this application.</summary>
    public ICollection<OAuthToken> Tokens { get; set; } = [];

    /// <summary>Authorization codes issued to this application.</summary>
    public ICollection<OAuthAuthorizationCode> AuthorizationCodes { get; set; } = [];
}
