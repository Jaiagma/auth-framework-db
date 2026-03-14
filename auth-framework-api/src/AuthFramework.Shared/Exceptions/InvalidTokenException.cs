namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when a token (JWT, reset token, verification token, etc.) is invalid or expired.</summary>
public class InvalidTokenException : AuthFrameworkException
{
    /// <inheritdoc/>
    public InvalidTokenException(string message)
        : base(message, "INVALID_TOKEN") { }

    /// <inheritdoc/>
    public InvalidTokenException(string message, Exception innerException)
        : base(message, innerException, "INVALID_TOKEN") { }
}
