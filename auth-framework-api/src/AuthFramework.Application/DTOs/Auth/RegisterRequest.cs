namespace AuthFramework.Application.DTOs.Auth;

/// <summary>Request payload for new user registration.</summary>
public sealed class RegisterRequest
{
    /// <summary>The user's email address.</summary>
    public string Email { get; init; } = string.Empty;

    /// <summary>Initial password (will be hashed before storage).</summary>
    public string Password { get; init; } = string.Empty;

    /// <summary>User's first name.</summary>
    public string? FirstName { get; init; }

    /// <summary>User's last name.</summary>
    public string? LastName { get; init; }

    /// <summary>Tenant the user is registering under.</summary>
    public Guid TenantId { get; init; }

    /// <summary>Preferred language code (e.g., "en-US").</summary>
    public string? Language { get; init; }

    /// <summary>Preferred timezone (e.g., "America/New_York").</summary>
    public string? Timezone { get; init; }
}
