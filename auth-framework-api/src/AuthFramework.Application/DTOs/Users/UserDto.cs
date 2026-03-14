using AuthFramework.Core.Enums;

namespace AuthFramework.Application.DTOs.Users;

/// <summary>Public-facing user data transfer object.</summary>
public sealed class UserDto
{
    /// <summary>User ID.</summary>
    public Guid Id { get; init; }

    /// <summary>User's email address.</summary>
    public string Email { get; init; } = string.Empty;

    /// <summary>First name (decrypted).</summary>
    public string? FirstName { get; init; }

    /// <summary>Last name (decrypted).</summary>
    public string? LastName { get; init; }

    /// <summary>Display name.</summary>
    public string? DisplayName { get; init; }

    /// <summary>Account status.</summary>
    public UserStatus Status { get; init; }

    /// <summary>Whether the email has been verified.</summary>
    public bool IsEmailVerified { get; init; }

    /// <summary>When the user account was created.</summary>
    public DateTimeOffset CreatedAt { get; init; }
}
