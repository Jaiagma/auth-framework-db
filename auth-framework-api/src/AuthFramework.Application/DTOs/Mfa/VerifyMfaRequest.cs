namespace AuthFramework.Application.DTOs.Mfa;

/// <summary>Request to verify an MFA code.</summary>
public sealed class VerifyMfaRequest
{
    /// <summary>ID of the pending MFA challenge.</summary>
    public Guid ChallengeId { get; init; }

    /// <summary>The OTP code entered by the user.</summary>
    public string Code { get; init; } = string.Empty;

    /// <summary>The device ID the code belongs to.</summary>
    public Guid? DeviceId { get; init; }
}
