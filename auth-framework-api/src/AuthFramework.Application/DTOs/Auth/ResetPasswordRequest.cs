namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request to set a new password using a reset token.</summary>
public sealed class ResetPasswordRequest
{
    /// <summary>The reset token received via email.</summary>
    public string Token { get; init; } = string.Empty;

    /// <summary>The new password to set.</summary>
    public string NewPassword { get; init; } = string.Empty;

    /// <summary>Tenant context.</summary>
    public Guid TenantId { get; init; }
}
