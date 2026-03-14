using System.Security.Claims;
using AuthFramework.Core.Constants;

namespace AuthFramework.Shared.Extensions;

/// <summary>Extension methods for extracting well-known claims from a <see cref="ClaimsPrincipal"/>.</summary>
public static class ClaimsPrincipalExtensions
{
    /// <summary>Extracts the user ID from the principal's claims. Returns <see cref="Guid.Empty"/> if not present.</summary>
    public static Guid GetUserId(this ClaimsPrincipal principal)
    {
        var claim = principal.FindFirst(AuthConstants.UserIdClaim)
                 ?? principal.FindFirst(ClaimTypes.NameIdentifier)
                 ?? principal.FindFirst(JwtRegisteredClaimNames.Sub);
        return Guid.TryParse(claim?.Value, out var id) ? id : Guid.Empty;
    }

    /// <summary>Extracts the tenant ID from the principal's claims. Returns <see cref="Guid.Empty"/> if not present.</summary>
    public static Guid GetTenantId(this ClaimsPrincipal principal)
    {
        var claim = principal.FindFirst(AuthConstants.TenantIdClaim);
        return Guid.TryParse(claim?.Value, out var id) ? id : Guid.Empty;
    }

    /// <summary>Extracts the session ID from the principal's claims. Returns <see cref="Guid.Empty"/> if not present.</summary>
    public static Guid GetSessionId(this ClaimsPrincipal principal)
    {
        var claim = principal.FindFirst(AuthConstants.SessionIdClaim);
        return Guid.TryParse(claim?.Value, out var id) ? id : Guid.Empty;
    }

    /// <summary>Extracts the email claim from the principal.</summary>
    public static string? GetEmail(this ClaimsPrincipal principal)
        => principal.FindFirst(ClaimTypes.Email)?.Value
        ?? principal.FindFirst(JwtRegisteredClaimNames.Email)?.Value;

    /// <summary>Returns true if the principal has the specified role.</summary>
    public static bool IsInRole(this ClaimsPrincipal principal, string role)
        => principal.HasClaim(ClaimTypes.Role, role);

    /// <summary>JWT registered claim names re-exported for convenience.</summary>
    private static class JwtRegisteredClaimNames
    {
        public const string Sub = "sub";
        public const string Email = "email";
    }
}
