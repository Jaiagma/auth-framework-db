namespace AuthFramework.Core.Constants;

/// <summary>Authorization policy name constants used across the API.</summary>
public static class PolicyNames
{
    /// <summary>Policy requiring any authenticated user.</summary>
    public const string AuthenticatedUser = "AuthenticatedUser";

    /// <summary>Policy restricting access to tenant administrators.</summary>
    public const string TenantAdmin = "TenantAdmin";

    /// <summary>Policy restricting access to super administrators.</summary>
    public const string SuperAdmin = "SuperAdmin";

    /// <summary>Policy for admin-only operations (tenant or super).</summary>
    public const string AdminOnly = "AdminOnly";

    /// <summary>Policy requiring verified email address.</summary>
    public const string VerifiedEmail = "VerifiedEmail";

    /// <summary>Policy requiring completed MFA.</summary>
    public const string MfaVerified = "MfaVerified";
}
