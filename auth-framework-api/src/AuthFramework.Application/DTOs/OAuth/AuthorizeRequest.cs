namespace AuthFramework.Application.DTOs.OAuth;

/// <summary>OAuth 2.0 authorization request parameters.</summary>
public sealed class AuthorizeRequest
{
    /// <summary>OAuth client ID.</summary>
    public string ClientId { get; init; } = string.Empty;

    /// <summary>URI to redirect after authorization.</summary>
    public string RedirectUri { get; init; } = string.Empty;

    /// <summary>Requested scopes (space-separated).</summary>
    public string? Scope { get; init; }

    /// <summary>CSRF protection state parameter.</summary>
    public string? State { get; init; }

    /// <summary>Response type (e.g., "code").</summary>
    public string ResponseType { get; init; } = "code";

    /// <summary>PKCE code challenge.</summary>
    public string? CodeChallenge { get; init; }

    /// <summary>PKCE code challenge method (e.g., "S256").</summary>
    public string? CodeChallengeMethod { get; init; }
}
