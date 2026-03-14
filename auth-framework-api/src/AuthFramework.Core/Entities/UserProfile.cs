namespace AuthFramework.Core.Entities;

/// <summary>Extended profile information for a user. PII fields are AES-256-GCM encrypted at rest.</summary>
public class UserProfile
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>Associated user ID.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant ID for row-level partitioning.</summary>
    public Guid TenantId { get; set; }

    /// <summary>Encrypted first name (PII).</summary>
    public string? FirstName { get; set; }

    /// <summary>Encrypted last name (PII).</summary>
    public string? LastName { get; set; }

    /// <summary>Display name shown in UI (may be public).</summary>
    public string? DisplayName { get; set; }

    /// <summary>Encrypted phone number (PII).</summary>
    public string? PhoneNumber { get; set; }

    /// <summary>URL to the user's avatar image.</summary>
    public string? AvatarUrl { get; set; }

    /// <summary>Preferred locale (e.g., "en-US").</summary>
    public string? Locale { get; set; }

    /// <summary>Preferred timezone (e.g., "America/New_York").</summary>
    public string? Timezone { get; set; }

    /// <summary>When the profile was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>When the profile was last updated.</summary>
    public DateTimeOffset UpdatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
