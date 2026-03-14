namespace AuthFramework.Core.Entities;

/// <summary>An issued OAuth 2.0 access and/or refresh token pair.</summary>
public class OAuthToken
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Application that was granted these tokens.</summary>
    public Guid ApplicationId { get; set; }

    /// <summary>User who authorized the token grant.</summary>
    public Guid? UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>The opaque or JWT access token value.</summary>
    public string AccessToken { get; set; } = string.Empty;

    /// <summary>The opaque refresh token value (hashed).</summary>
    public string? RefreshToken { get; set; }

    /// <summary>Granted scopes.</summary>
    public string[] Scopes { get; set; } = [];

    /// <summary>When the access token expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>When the refresh token expires.</summary>
    public DateTimeOffset? RefreshExpiresAt { get; set; }

    /// <summary>When the token was revoked.</summary>
    public DateTimeOffset? RevokedAt { get; set; }

    /// <summary>When the token was issued.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>The application that owns this token.</summary>
    public OAuthApplication? Application { get; set; }
}
