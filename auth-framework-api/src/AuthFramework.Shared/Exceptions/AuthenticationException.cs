namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when authentication fails (invalid credentials, account issues, etc.).</summary>
public class AuthenticationException : AuthFrameworkException
{
    /// <inheritdoc/>
    public AuthenticationException(string message)
        : base(message, "AUTHENTICATION_FAILED") { }

    /// <inheritdoc/>
    public AuthenticationException(string message, Exception innerException)
        : base(message, innerException, "AUTHENTICATION_FAILED") { }
}
