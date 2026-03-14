using AuthFramework.Application.DTOs.Auth;

namespace AuthFramework.Application.Interfaces;

/// <summary>Core authentication operations: registration, login, token management.</summary>
public interface IAuthenticationService
{
    /// <summary>Registers a new user account within a tenant.</summary>
    Task<LoginResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default);

    /// <summary>Authenticates a user and returns tokens (or an MFA challenge).</summary>
    Task<LoginResponse> LoginAsync(LoginRequest request, string? ipAddress = null, string? userAgent = null, CancellationToken cancellationToken = default);

    /// <summary>Revokes the current session, logging the user out.</summary>
    Task LogoutAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default);

    /// <summary>Issues new access and refresh tokens using a valid refresh token.</summary>
    Task<LoginResponse> RefreshTokenAsync(RefreshTokenRequest request, CancellationToken cancellationToken = default);

    /// <summary>Changes a user's password after verifying the current password.</summary>
    Task ChangePasswordAsync(Guid userId, Guid tenantId, ChangePasswordRequest request, CancellationToken cancellationToken = default);

    /// <summary>Creates a password reset token and triggers a reset email.</summary>
    Task RequestPasswordResetAsync(PasswordResetRequest request, CancellationToken cancellationToken = default);

    /// <summary>Validates a reset token and sets a new password.</summary>
    Task ResetPasswordAsync(ResetPasswordRequest request, CancellationToken cancellationToken = default);

    /// <summary>Marks the user's email as verified using a verification token.</summary>
    Task VerifyEmailAsync(string token, Guid tenantId, CancellationToken cancellationToken = default);
}
