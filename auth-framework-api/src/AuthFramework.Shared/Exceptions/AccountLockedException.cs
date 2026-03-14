namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when a login attempt is made on a locked account.</summary>
public class AccountLockedException : AuthFrameworkException
{
    /// <summary>When the account lock expires.</summary>
    public DateTimeOffset LockedUntil { get; }

    /// <inheritdoc/>
    public AccountLockedException(DateTimeOffset lockedUntil)
        : base($"Account is locked until {lockedUntil:O}. Please try again later.", "ACCOUNT_LOCKED")
    {
        LockedUntil = lockedUntil;
    }
}
