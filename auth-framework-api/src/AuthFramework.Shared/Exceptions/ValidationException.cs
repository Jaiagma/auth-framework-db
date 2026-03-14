namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when input validation fails.</summary>
public class ValidationException : AuthFrameworkException
{
    /// <summary>Individual validation error messages.</summary>
    public IReadOnlyList<string> Errors { get; }

    /// <inheritdoc/>
    public ValidationException(string message)
        : base(message, "VALIDATION_ERROR")
    {
        Errors = [message];
    }

    /// <inheritdoc/>
    public ValidationException(IEnumerable<string> errors)
        : base(string.Join("; ", errors), "VALIDATION_ERROR")
    {
        Errors = errors.ToList();
    }
}
