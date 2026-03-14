namespace AuthFramework.Core.Entities;

/// <summary>Tracks an active SSO session with an external identity provider.</summary>
public class SsoSession
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Local user associated with the SSO session.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>The identity provider for this SSO session.</summary>
    public Guid ProviderId { get; set; }

    /// <summary>Session identifier at the external identity provider.</summary>
    public string? ExternalSessionId { get; set; }

    /// <summary>When the SSO session expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>When the SSO session was established.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }

    /// <summary>Identity provider for this session.</summary>
    public IdentityProvider? Provider { get; set; }
}
