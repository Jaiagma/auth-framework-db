using AuthFramework.Core.Enums;

namespace AuthFramework.Application.DTOs.Mfa;

/// <summary>Response after enrolling an MFA device.</summary>
public sealed class EnrollMfaResponse
{
    /// <summary>ID of the newly created MFA device.</summary>
    public Guid DeviceId { get; init; }

    /// <summary>TOTP secret key (only for TOTP enrollments).</summary>
    public string? Secret { get; init; }

    /// <summary>TOTP QR code URI (only for TOTP enrollments).</summary>
    public string? QrCodeUri { get; init; }

    /// <summary>Enrolled method type.</summary>
    public MfaMethodType MethodType { get; init; }
}

/// <summary>Summary of an enrolled MFA device.</summary>
public sealed class MfaDeviceDto
{
    /// <summary>Device ID.</summary>
    public Guid Id { get; init; }

    /// <summary>MFA method type.</summary>
    public MfaMethodType MethodType { get; init; }

    /// <summary>User-assigned name.</summary>
    public string? Name { get; init; }

    /// <summary>Whether the device is active and verified.</summary>
    public bool IsVerified { get; init; }

    /// <summary>Last time this device was used.</summary>
    public DateTimeOffset? LastUsedAt { get; init; }

    /// <summary>When the device was registered.</summary>
    public DateTimeOffset CreatedAt { get; init; }
}
