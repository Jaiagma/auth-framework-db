namespace AuthFramework.Application.DTOs.Users;

/// <summary>Request to update a user's profile.</summary>
public sealed class UpdateProfileRequest
{
    /// <summary>Updated first name.</summary>
    public string? FirstName { get; init; }

    /// <summary>Updated last name.</summary>
    public string? LastName { get; init; }

    /// <summary>Updated display name.</summary>
    public string? DisplayName { get; init; }

    /// <summary>Updated preferred language code.</summary>
    public string? Language { get; init; }

    /// <summary>Updated preferred timezone.</summary>
    public string? Timezone { get; init; }
}
