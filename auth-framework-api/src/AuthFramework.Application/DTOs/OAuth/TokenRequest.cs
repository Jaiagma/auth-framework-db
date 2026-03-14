namespace AuthFramework.Application.DTOs.OAuth;

/// <summary>OAuth 2.0 token endpoint request.</summary>
public sealed class TokenRequest
{
    /// <summary>Grant type (authorization_code, refresh_token, client_credentials).</summary>
    public string GrantType { get; init; } = string.Empty;

    /// <summary>Authorization code (for authorization_code grant).</summary>
    public string? Code { get; init; }

    /// <summary>Refresh token (for refresh_token grant).</summary>
    public string? RefreshToken { get; init; }

    /// <summary>OAuth client ID.</summary>
    public string ClientId { get; init; } = string.Empty;

    /// <summary>OAuth client secret.</summary>
    public string? ClientSecret { get; init; }

    /// <summary>Redirect URI (must match authorization request).</summary>
    public string? RedirectUri { get; init; }

    /// <summary>PKCE code verifier.</summary>
    public string? CodeVerifier { get; init; }
}
