namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request to initiate a password reset flow.</summary>
public sealed class PasswordResetRequest
{
    /// <summary>Email address to send the reset link to.</summary>
    public string Email { get; init; } = string.Empty;

    /// <summary>Tenant context.</summary>
    public Guid TenantId { get; init; }
}
