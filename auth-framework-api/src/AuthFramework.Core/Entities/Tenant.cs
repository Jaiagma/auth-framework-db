using System.Text.Json;
using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>Represents a tenant (top-level isolated organizational unit) in the auth framework.</summary>
public class Tenant
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Internal unique name/identifier for the tenant.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>URL-safe slug for subdomain or path routing.</summary>
    public string Slug { get; set; } = string.Empty;

    /// <summary>Human-readable display name.</summary>
    public string? DisplayName { get; set; }

    /// <summary>URL to the tenant's logo image.</summary>
    public string? LogoUrl { get; set; }

    /// <summary>Current lifecycle status.</summary>
    public TenantStatus Status { get; set; } = TenantStatus.Active;

    /// <summary>Subscription plan identifier.</summary>
    public string? Plan { get; set; }

    /// <summary>Data residency region (e.g., "us-east-1", "eu-west-1").</summary>
    public string? DataResidency { get; set; }

    /// <summary>Maximum number of users allowed for this tenant.</summary>
    public int? MaxUsers { get; set; }

    /// <summary>Maximum number of applications allowed for this tenant.</summary>
    public int? MaxApplications { get; set; }

    /// <summary>Comma-separated or JSON array of allowed MFA methods.</summary>
    public string[]? AllowedMfaMethods { get; set; }

    /// <summary>Whether MFA is required for all users in this tenant.</summary>
    public bool RequireMfa { get; set; }

    /// <summary>Default session lifetime in seconds.</summary>
    public int SessionLifetimeSec { get; set; } = 3600;

    /// <summary>Arbitrary tenant-level metadata stored as JSONB.</summary>
    public JsonDocument? Metadata { get; set; }

    /// <summary>When the tenant was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the tenant was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    /// <summary>Soft-delete timestamp.</summary>
    public DateTimeOffset? DeletedAt { get; set; }

    // Navigation
    /// <summary>Users belonging to this tenant.</summary>
    public ICollection<User> Users { get; set; } = [];

    /// <summary>Applications registered under this tenant.</summary>
    public ICollection<Application> Applications { get; set; } = [];
}
