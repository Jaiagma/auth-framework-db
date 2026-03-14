namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when a referenced user cannot be found.</summary>
public class UserNotFoundException : AuthFrameworkException
{
    /// <summary>The user ID that was not found.</summary>
    public Guid UserId { get; }

    /// <inheritdoc/>
    public UserNotFoundException(Guid userId)
        : base($"User '{userId}' was not found.", "USER_NOT_FOUND")
    {
        UserId = userId;
    }
}
