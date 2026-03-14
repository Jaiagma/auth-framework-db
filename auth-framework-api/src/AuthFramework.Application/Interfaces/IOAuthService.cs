using AuthFramework.Application.DTOs.OAuth;

namespace AuthFramework.Application.Interfaces;

/// <summary>OAuth 2.0 authorization server operations.</summary>
public interface IOAuthService
{
    /// <summary>Creates a new OAuth application registration.</summary>
    Task<OAuthApplicationDto> CreateApplicationAsync(Guid tenantId, CreateApplicationRequest request, CancellationToken cancellationToken = default);

    /// <summary>Retrieves an OAuth application by its internal ID.</summary>
    Task<OAuthApplicationDto?> GetApplicationAsync(Guid applicationId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Processes an authorization request and returns an authorization code.</summary>
    Task<string> AuthorizeAsync(Guid userId, Guid tenantId, AuthorizeRequest request, CancellationToken cancellationToken = default);

    /// <summary>Exchanges an authorization code or refresh token for an access token.</summary>
    Task<TokenResponse> ExchangeCodeAsync(TokenRequest request, CancellationToken cancellationToken = default);

    /// <summary>Revokes an access or refresh token.</summary>
    Task RevokeTokenAsync(string token, string? tokenTypeHint, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Introspects a token and returns its metadata (RFC 7662).</summary>
    Task<TokenIntrospectionResponse> IntrospectTokenAsync(string token, Guid tenantId, CancellationToken cancellationToken = default);
}
