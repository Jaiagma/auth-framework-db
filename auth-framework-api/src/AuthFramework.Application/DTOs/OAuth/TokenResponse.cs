using System.Text.Json.Serialization;

namespace AuthFramework.Application.DTOs.OAuth;

/// <summary>OAuth 2.0 token endpoint response.</summary>
public sealed class TokenResponse
{
    /// <summary>JWT access token.</summary>
    [JsonPropertyName("access_token")]
    public string AccessToken { get; init; } = string.Empty;

    /// <summary>Opaque refresh token.</summary>
    [JsonPropertyName("refresh_token")]
    public string? RefreshToken { get; init; }

    /// <summary>Access token lifetime in seconds.</summary>
    [JsonPropertyName("expires_in")]
    public int ExpiresIn { get; init; }

    /// <summary>Token type, always "Bearer".</summary>
    [JsonPropertyName("token_type")]
    public string TokenType { get; init; } = "Bearer";

    /// <summary>Granted scopes (space-separated).</summary>
    [JsonPropertyName("scope")]
    public string? Scope { get; init; }
}

/// <summary>Token introspection response (RFC 7662).</summary>
public sealed class TokenIntrospectionResponse
{
    /// <summary>Whether the token is currently active.</summary>
    [JsonPropertyName("active")]
    public bool Active { get; init; }

    /// <summary>Token subject (user ID).</summary>
    [JsonPropertyName("sub")]
    public string? Sub { get; init; }

    /// <summary>Token expiry as Unix timestamp.</summary>
    [JsonPropertyName("exp")]
    public long? Exp { get; init; }

    /// <summary>Granted scopes.</summary>
    [JsonPropertyName("scope")]
    public string? Scope { get; init; }

    /// <summary>Client ID that owns the token.</summary>
    [JsonPropertyName("client_id")]
    public string? ClientId { get; init; }
}
