namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request to change a password when the current password is known.</summary>
public sealed class ChangePasswordRequest
{
    /// <summary>Current password for verification.</summary>
    public string CurrentPassword { get; init; } = string.Empty;

    /// <summary>New password to set.</summary>
    public string NewPassword { get; init; } = string.Empty;
}
