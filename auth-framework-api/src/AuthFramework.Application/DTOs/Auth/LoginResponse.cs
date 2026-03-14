using AuthFramework.Application.DTOs.Users;

namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Response from a successful login or token refresh.</summary>
public sealed class LoginResponse
{
    /// <summary>JWT access token. Null if MFA is required.</summary>
    public string? AccessToken { get; init; }

    /// <summary>Opaque refresh token. Null if MFA is required.</summary>
    public string? RefreshToken { get; init; }

    /// <summary>Access token lifetime in seconds.</summary>
    public int ExpiresIn { get; init; }

    /// <summary>Token type, always "Bearer".</summary>
    public string TokenType { get; init; } = "Bearer";

    /// <summary>Whether the client must complete an MFA challenge before receiving tokens.</summary>
    public bool MfaRequired { get; init; }

    /// <summary>Challenge ID to use when calling the MFA verify endpoint.</summary>
    public Guid? MfaChallengeId { get; init; }

    /// <summary>Basic user information.</summary>
    public UserDto? User { get; init; }
}
