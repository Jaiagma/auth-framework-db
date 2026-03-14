using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>A registered MFA device or method for a user.</summary>
public class MfaDevice
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User who owns this device.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>MFA method type.</summary>
    public MfaMethodType MethodType { get; set; }

    /// <summary>User-assigned friendly name for the device.</summary>
    public string? Name { get; set; }

    /// <summary>TOTP secret key (encrypted).</summary>
    public string? SecretKey { get; set; }

    /// <summary>Phone number for SMS MFA (encrypted).</summary>
    public string? PhoneNumber { get; set; }

    /// <summary>Email address for email MFA.</summary>
    public string? Email { get; set; }

    /// <summary>Whether this device is active and usable.</summary>
    public bool IsActive { get; set; } = true;

    /// <summary>Whether the device has been verified by the user.</summary>
    public bool IsVerified { get; set; }

    /// <summary>When this device was last used for authentication.</summary>
    public DateTimeOffset? LastUsedAt { get; set; }

    /// <summary>When the device was registered.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
