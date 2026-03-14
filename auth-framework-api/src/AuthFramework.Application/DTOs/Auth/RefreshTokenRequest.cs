namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request to exchange a refresh token for new tokens.</summary>
public sealed class RefreshTokenRequest
{
    /// <summary>The refresh token to exchange.</summary>
    public string RefreshToken { get; init; } = string.Empty;

    /// <summary>Tenant context.</summary>
    public Guid TenantId { get; init; }
}
