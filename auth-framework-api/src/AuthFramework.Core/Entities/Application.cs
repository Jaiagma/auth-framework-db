using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>An application registered in the tenant's ecosystem (distinct from OAuth applications).</summary>
public class Application
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Tenant that owns this application.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Human-readable application name.</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>Type of application.</summary>
    public ApplicationType ApplicationType { get; set; }

    /// <summary>Unique client identifier for this application.</summary>
    public string ClientId { get; set; } = string.Empty;

    /// <summary>Whether the application is active.</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>Allowed callback/redirect URLs.</summary>
    public string[] CallbackUrls { get; set; } = [];

    /// <summary>When the application was registered.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the application was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>Tenant that owns this application.</summary>
    public Tenant? Tenant { get; set; }
}
