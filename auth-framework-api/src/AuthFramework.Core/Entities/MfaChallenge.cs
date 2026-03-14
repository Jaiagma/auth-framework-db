namespace AuthFramework.Core.Entities;

/// <summary>An in-progress MFA challenge created during login.</summary>
public class MfaChallenge
{
    /// <summary>Unique identifier (UUID v7).</summary>
    public Guid Id { get; set; }

    /// <summary>User being challenged.</summary>
    public Guid UserId { get; set; }

    /// <summary>Tenant for row-level security.</summary>
    public Guid TenantId { get; set; }

    /// <summary>The MFA device the challenge was sent to.</summary>
    public Guid? DeviceId { get; set; }

    /// <summary>The OTP or challenge code (hashed for storage).</summary>
    public string? ChallengeCode { get; set; }

    /// <summary>When this challenge expires.</summary>
    public DateTimeOffset ExpiresAt { get; set; }

    /// <summary>When the challenge was successfully verified.</summary>
    public DateTimeOffset? VerifiedAt { get; set; }

    /// <summary>When the challenge was created.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>Associated user.</summary>
    public User? User { get; set; }
}
