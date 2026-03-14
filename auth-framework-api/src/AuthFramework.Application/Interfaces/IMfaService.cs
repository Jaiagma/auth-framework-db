using AuthFramework.Application.DTOs.Mfa;

namespace AuthFramework.Application.Interfaces;

/// <summary>Multi-factor authentication enrollment and verification operations.</summary>
public interface IMfaService
{
    /// <summary>Enrolls a new MFA device/method for the user.</summary>
    Task<EnrollMfaResponse> EnrollDeviceAsync(Guid userId, Guid tenantId, EnrollMfaRequest request, CancellationToken cancellationToken = default);

    /// <summary>Verifies an MFA code for a pending challenge.</summary>
    Task<bool> VerifyMfaAsync(Guid tenantId, VerifyMfaRequest request, CancellationToken cancellationToken = default);

    /// <summary>Lists all MFA devices registered for a user.</summary>
    Task<IReadOnlyList<MfaDeviceDto>> GetDevicesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Removes (deactivates) an MFA device.</summary>
    Task RemoveDeviceAsync(Guid userId, Guid tenantId, Guid deviceId, CancellationToken cancellationToken = default);

    /// <summary>Generates and stores a new set of recovery codes, replacing any existing ones.</summary>
    Task<IReadOnlyList<string>> GenerateRecoveryCodesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Validates a recovery code and marks it as used.</summary>
    Task<bool> VerifyRecoveryCodeAsync(Guid userId, Guid tenantId, string code, CancellationToken cancellationToken = default);
}
