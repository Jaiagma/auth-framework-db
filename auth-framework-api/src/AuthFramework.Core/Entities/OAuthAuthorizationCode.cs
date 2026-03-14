namespace AuthFramework.Core.Entities;

/// <summary>A single-use OAuth 2.0 authorization code from the authorization code flow.</summary>
public class OAuthAuthorizationCode
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Application that requested the code.</summary>
    public Guid ApplicationId { get; set; }

    /// <summary>User who authorized the request.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>The authorization code value.</summary>
    public string Code { get; set; } = string.Empty;

    /// <summary>The redirect URI that was used in the authorization request.</summary>
    public string RedirectUri { get; set; } = string.Empty;

    /// <summary>Scopes granted.</summary>
    public string[] Scopes { get; set; } = [];

    /// <summary>When the code expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>When the code was exchanged (null if unused).</summary>
    public DateTimeOffset? UsedAt { get; set; }

    /// <summary>When the code was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>The application that owns this code.</summary>
    public OAuthApplication? Application { get; set; }
}
