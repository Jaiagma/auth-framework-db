namespace AuthFramework.Core.Entities;

/// <summary>Represents an active or historical user session.</summary>
public class UserSession
{
    /// <summary>Unique session identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User who owns the session.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Application through which the session was created.</summary>
    public Guid? ApplicationId { get; set; }

    /// <summary>IP address of the client at session creation.</summary>
    public string? IpAddress { get; set; }

    /// <summary>User-Agent string of the client.</summary>
    public string? UserAgent { get; set; }

    /// <summary>Device fingerprint reference for anomaly detection.</summary>
    public Guid? DeviceFingerprintId { get; set; }

    /// <summary>Whether MFA was completed for this session.</summary>
    public bool MfaVerified { get; set; }

    /// <summary>When the session expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>Most recent activity timestamp (updated on each request).</summary>
    public DateTimeOffset LastActivityAt { get; set; }

    /// <summary>When the session was explicitly revoked.</summary>
    public DateTimeOffset? RevokedAt { get; set; }

    /// <summary>When the session was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
