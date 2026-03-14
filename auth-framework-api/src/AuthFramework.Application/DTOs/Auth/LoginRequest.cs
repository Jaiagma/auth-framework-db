namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request payload for user login.</summary>
public sealed class LoginRequest
{
    /// <summary>The user's email address.</summary>
    public string Email { get; init; } = string.Empty;

    /// <summary>The user's password.</summary>
    public string Password { get; init; } = string.Empty;

    /// <summary>Tenant context for the login.</summary>
    public Guid TenantId { get; init; }

    /// <summary>Optional device information for fingerprinting.</summary>
    public string? DeviceInfo { get; init; }
}
