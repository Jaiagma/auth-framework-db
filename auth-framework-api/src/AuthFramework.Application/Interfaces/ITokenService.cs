using System.Security.Claims;
using AuthFramework.Core.Entities;

namespace AuthFramework.Application.Interfaces;

/// <summary>Service for generating and validating JWT tokens.</summary>
public interface ITokenService
{
    /// <summary>Generates a signed JWT access token for the given user and session.</summary>
    string GenerateAccessToken(User user, Guid sessionId, IEnumerable<string>? additionalScopes = null);

    /// <summary>Generates a cryptographically random opaque refresh token.</summary>
    string GenerateRefreshToken();

    /// <summary>Validates a JWT token and returns the ClaimsPrincipal if valid.</summary>
    ClaimsPrincipal? ValidateToken(string token);

    /// <summary>Extracts claims from a token without full validation (e.g., for expired tokens during refresh).</summary>
    ClaimsPrincipal? GetClaimsFromToken(string token);
}
