namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when an operation requires MFA to be completed first.</summary>
public class MfaRequiredException : AuthFrameworkException
{
    /// <summary>The MFA challenge ID that must be completed.</summary>
    public Guid? ChallengeId { get; }

    /// <inheritdoc/>
    public MfaRequiredException(Guid? challengeId = null)
        : base("Multi-factor authentication is required to complete this action.", "MFA_REQUIRED")
    {
        ChallengeId = challengeId;
    }
}
