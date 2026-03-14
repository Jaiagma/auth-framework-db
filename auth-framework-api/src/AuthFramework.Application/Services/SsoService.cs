using AuthFramework.Application.Interfaces;
using Microsoft.Extensions.Logging;

namespace AuthFramework.Application.Services;

/// <summary>Stub SSO service - full SAML/OIDC implementation would integrate with provider SDKs.</summary>
public sealed class SsoService : ISsoService
{
    private readonly ILogger<SsoService> _logger;

    public SsoService(ILogger<SsoService> logger) => _logger = logger;

    /// <inheritdoc/>
    public Task<IReadOnlyList<SsoProviderDto>> GetProvidersAsync(Guid tenantId, CancellationToken cancellationToken = default)
    {
        _logger.LogDebug("GetProviders called for tenant {TenantId}", tenantId);
        return Task.FromResult<IReadOnlyList<SsoProviderDto>>([]);
    }

    /// <inheritdoc/>
    public Task<string> InitiateSsoAsync(Guid tenantId, string providerName, string? returnUrl = null, CancellationToken cancellationToken = default)
        => throw new NotImplementedException("SSO provider integration not yet implemented.");

    /// <inheritdoc/>
    public Task<SsoCallbackResult> ProcessSsoCallbackAsync(Guid tenantId, string providerName, string code, string? state = null, CancellationToken cancellationToken = default)
        => throw new NotImplementedException("SSO callback processing not yet implemented.");

    /// <inheritdoc/>
    public Task<SsoSessionDto?> GetSsoSessionAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default)
        => Task.FromResult<SsoSessionDto?>(null);
}
