using AuthFramework.Core.Enums;

namespace AuthFramework.Application.DTOs.Mfa;

/// <summary>Request to enroll a new MFA device or method.</summary>
public sealed class EnrollMfaRequest
{
    /// <summary>Type of MFA method to enroll.</summary>
    public MfaMethodType MethodType { get; init; }

    /// <summary>Phone number for SMS-based MFA.</summary>
    public string? PhoneNumber { get; init; }

    /// <summary>Email address for email-based MFA.</summary>
    public string? Email { get; init; }

    /// <summary>Friendly name for the device.</summary>
    public string? DeviceName { get; init; }
}
