using AuthFramework.Core.Constants;
using AuthFramework.Shared.Exceptions;

namespace AuthFramework.Shared.Utilities;

/// <summary>Enforces password strength requirements.</summary>
public static class PasswordValidator
{
    /// <summary>
    /// Validates a password against the configured strength rules.
    /// Throws <see cref="ValidationException"/> if the password does not meet requirements.
    /// </summary>
    /// <param name="password">The plaintext password to validate.</param>
    public static void Validate(string password)
    {
        var errors = new List<string>();

        if (string.IsNullOrEmpty(password))
        {
            errors.Add("Password is required.");
        }
        else
        {
            if (password.Length < AuthConstants.MinPasswordLength)
                errors.Add($"Password must be at least {AuthConstants.MinPasswordLength} characters long.");

            if (password.Length > AuthConstants.MaxPasswordLength)
                errors.Add($"Password must not exceed {AuthConstants.MaxPasswordLength} characters.");

            if (!password.Any(char.IsUpper))
                errors.Add("Password must contain at least one uppercase letter.");

            if (!password.Any(char.IsLower))
                errors.Add("Password must contain at least one lowercase letter.");

            if (!password.Any(char.IsDigit))
                errors.Add("Password must contain at least one digit.");

            if (!password.Any(IsSpecialCharacter))
                errors.Add("Password must contain at least one special character (!@#$%^&*()_+-=[]{}|;':\",./<>?).");
        }

        if (errors.Count > 0)
            throw new Exceptions.ValidationException(string.Join(" ", errors));
    }

    /// <summary>Returns true if the password meets all strength requirements.</summary>
    public static bool IsValid(string password)
    {
        try
        {
            Validate(password);
            return true;
        }
        catch (Exceptions.ValidationException)
        {
            return false;
        }
    }

    private static bool IsSpecialCharacter(char c)
        => "!@#$%^&*()_+-=[]{}|;':\",./<>?".Contains(c);
}
