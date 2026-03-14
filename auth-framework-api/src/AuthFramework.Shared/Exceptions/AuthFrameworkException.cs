namespace AuthFramework.Shared.Exceptions;

/// <summary>Base exception for all AuthFramework application errors.</summary>
public class AuthFrameworkException : Exception
{
    /// <summary>Machine-readable error code.</summary>
    public string ErrorCode { get; }

    /// <inheritdoc/>
    public AuthFrameworkException(string message, string errorCode = "AUTH_ERROR")
        : base(message)
    {
        ErrorCode = errorCode;
    }

    /// <inheritdoc/>
    public AuthFrameworkException(string message, Exception innerException, string errorCode = "AUTH_ERROR")
        : base(message, innerException)
    {
        ErrorCode = errorCode;
    }
}
