namespace AuthFramework.Application.Interfaces;

/// <summary>Single Sign-On operations with external identity providers.</summary>
public interface ISsoService
{
    /// <summary>Returns the list of active SSO providers for a tenant.</summary>
    Task<IReadOnlyList<SsoProviderDto>> GetProvidersAsync(Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Initiates an SSO login flow and returns a redirect URL to the provider.</summary>
    Task<string> InitiateSsoAsync(Guid tenantId, string providerName, string? returnUrl = null, CancellationToken cancellationToken = default);

    /// <summary>Processes the callback from an SSO provider and creates/matches a local user.</summary>
    Task<SsoCallbackResult> ProcessSsoCallbackAsync(Guid tenantId, string providerName, string code, string? state = null, CancellationToken cancellationToken = default);

    /// <summary>Gets the current SSO session for a user.</summary>
    Task<SsoSessionDto?> GetSsoSessionAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);
}

/// <summary>Information about an SSO provider available to a tenant.</summary>
public record SsoProviderDto(Guid Id, string Name, string ProviderType, bool IsActive);

/// <summary>Result of processing an SSO callback.</summary>
public record SsoCallbackResult(bool Success, string? AccessToken, string? RefreshToken, string? ErrorMessage);

/// <summary>Current SSO session details.</summary>
public record SsoSessionDto(Guid Id, Guid ProviderId, string ProviderName, DateTimeOffset ExpiresAt);
