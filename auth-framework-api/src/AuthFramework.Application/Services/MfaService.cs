using AuthFramework.Application.DTOs.Mfa;
using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Shared.Exceptions;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Logging;
using System.Security.Cryptography;

namespace AuthFramework.Application.Services;

/// <summary>Handles MFA device enrollment, verification, and recovery code management.</summary>
public sealed class MfaService : IMfaService
{
    private readonly IRepository<MfaDevice> _deviceRepository;
    private readonly IRepository<MfaChallenge> _challengeRepository;
    private readonly IRepository<MfaRecoveryCode> _recoveryCodeRepository;
    private readonly IEncryptionService _encryptionService;
    private readonly ILogger<MfaService> _logger;

    public MfaService(
        IRepository<MfaDevice> deviceRepository,
        IRepository<MfaChallenge> challengeRepository,
        IRepository<MfaRecoveryCode> recoveryCodeRepository,
        IEncryptionService encryptionService,
        ILogger<MfaService> logger)
    {
        _deviceRepository = deviceRepository;
        _challengeRepository = challengeRepository;
        _recoveryCodeRepository = recoveryCodeRepository;
        _encryptionService = encryptionService;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<EnrollMfaResponse> EnrollDeviceAsync(Guid userId, Guid tenantId, EnrollMfaRequest request, CancellationToken cancellationToken = default)
    {
        string? secret = null;
        string? qrCodeUri = null;

        if (request.MethodType == MfaMethodType.Totp)
        {
            var rawSecret = new byte[20];
            RandomNumberGenerator.Fill(rawSecret);
            secret = TotpHelper.ToBase32(rawSecret);
            qrCodeUri = TotpHelper.GenerateQrCodeUri("AuthFramework", userId.ToString(), secret);
        }

        var device = new MfaDevice
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = tenantId,
            MethodType = request.MethodType,
            Name = request.DeviceName,
            SecretKey = secret != null ? _encryptionService.Encrypt(secret) : null,
            PhoneNumber = request.PhoneNumber != null ? _encryptionService.Encrypt(request.PhoneNumber) : null,
            Email = request.Email,
            IsActive = true,
            IsVerified = false,
            CreatedAt = DateTimeOffset.UtcNow,
        };

        await _deviceRepository.AddAsync(device, cancellationToken);

        _logger.LogInformation("MFA device {DeviceId} enrolled for user {UserId} (type: {Type})", device.Id, userId, request.MethodType);

        return new EnrollMfaResponse
        {
            DeviceId = device.Id,
            Secret = secret,
            QrCodeUri = qrCodeUri,
            MethodType = request.MethodType,
        };
    }

    /// <inheritdoc/>
    public async Task<bool> VerifyMfaAsync(Guid tenantId, VerifyMfaRequest request, CancellationToken cancellationToken = default)
    {
        var challenges = await _challengeRepository.FindAsync(
            c => c.Id == request.ChallengeId && c.TenantId == tenantId
                 && c.VerifiedAt == null && c.ExpiresAt > DateTimeOffset.UtcNow,
            cancellationToken: cancellationToken);

        var challenge = challenges.Items.FirstOrDefault()
            ?? throw new InvalidTokenException("MFA challenge not found or expired.");

        if (request.DeviceId.HasValue)
        {
            var device = await _deviceRepository.GetByIdAsync(request.DeviceId.Value, cancellationToken);
            if (device is null || !device.IsActive) return false;

            if (device.MethodType == MfaMethodType.Totp && device.SecretKey != null)
            {
                var decryptedSecret = _encryptionService.Decrypt(device.SecretKey);
                var isValid = TotpHelper.VerifyCode(decryptedSecret, request.Code);
                if (isValid)
                {
                    challenge.VerifiedAt = DateTimeOffset.UtcNow;
                    await _challengeRepository.UpdateAsync(challenge, cancellationToken);
                    device.LastUsedAt = DateTimeOffset.UtcNow;
                    await _deviceRepository.UpdateAsync(device, cancellationToken);
                }
                return isValid;
            }
        }

        // For SMS/Email: compare challenge code
        if (challenge.ChallengeCode != null)
        {
            var isValid = _encryptionService.VerifyHash(request.Code, challenge.ChallengeCode);
            if (isValid)
            {
                challenge.VerifiedAt = DateTimeOffset.UtcNow;
                await _challengeRepository.UpdateAsync(challenge, cancellationToken);
            }
            return isValid;
        }

        return false;
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<MfaDeviceDto>> GetDevicesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var result = await _deviceRepository.FindAsync(
            d => d.UserId == userId && d.TenantId == tenantId && d.IsActive,
            1, 100, cancellationToken);

        return result.Items.Select(d => new MfaDeviceDto
        {
            Id = d.Id,
            MethodType = d.MethodType,
            Name = d.Name,
            IsVerified = d.IsVerified,
            LastUsedAt = d.LastUsedAt,
            CreatedAt = d.CreatedAt,
        }).ToList();
    }

    /// <inheritdoc/>
    public async Task RemoveDeviceAsync(Guid userId, Guid tenantId, Guid deviceId, CancellationToken cancellationToken = default)
    {
        var device = await _deviceRepository.GetByIdAsync(deviceId, cancellationToken)
            ?? throw new AuthFrameworkException("MFA device not found.");

        if (device.UserId != userId || device.TenantId != tenantId)
            throw new AuthFrameworkException("Access denied.");

        device.IsActive = false;
        await _deviceRepository.UpdateAsync(device, cancellationToken);
        _logger.LogInformation("MFA device {DeviceId} removed for user {UserId}", deviceId, userId);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<string>> GenerateRecoveryCodesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        // Invalidate existing codes
        var existing = await _recoveryCodeRepository.FindAsync(
            r => r.UserId == userId && r.TenantId == tenantId && r.UsedAt == null,
            1, 100, cancellationToken);

        foreach (var old in existing.Items)
        {
            old.UsedAt = DateTimeOffset.UtcNow;
            await _recoveryCodeRepository.UpdateAsync(old, cancellationToken);
        }

        var codes = new List<string>(AuthConstants.RecoveryCodeCount);
        for (var i = 0; i < AuthConstants.RecoveryCodeCount; i++)
        {
            var rawCode = GenerateRecoveryCode();
            codes.Add(rawCode);

            var entity = new MfaRecoveryCode
            {
                Id = UuidV7Generator.NewGuid(),
                UserId = userId,
                TenantId = tenantId,
                CodeHash = _encryptionService.Hash(rawCode),
                CreatedAt = DateTimeOffset.UtcNow,
            };
            await _recoveryCodeRepository.AddAsync(entity, cancellationToken);
        }

        _logger.LogInformation("Generated {Count} recovery codes for user {UserId}", codes.Count, userId);
        return codes;
    }

    /// <inheritdoc/>
    public async Task<bool> VerifyRecoveryCodeAsync(Guid userId, Guid tenantId, string code, CancellationToken cancellationToken = default)
    {
        var codeHash = _encryptionService.Hash(code);
        var results = await _recoveryCodeRepository.FindAsync(
            r => r.UserId == userId && r.TenantId == tenantId && r.CodeHash == codeHash && r.UsedAt == null,
            cancellationToken: cancellationToken);

        var recoveryCode = results.Items.FirstOrDefault();
        if (recoveryCode is null) return false;

        recoveryCode.UsedAt = DateTimeOffset.UtcNow;
        await _recoveryCodeRepository.UpdateAsync(recoveryCode, cancellationToken);
        return true;
    }

    private static string GenerateRecoveryCode()
    {
        // 12 random bytes → 12 independent characters, formatted as XXXX-XXXX-XXXX
        var bytes = new byte[12];
        RandomNumberGenerator.Fill(bytes);
        const string chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        return string.Create(14, bytes, (span, b) =>
        {
            for (var i = 0; i < 4; i++) span[i] = chars[b[i] % chars.Length];
            span[4] = '-';
            for (var i = 0; i < 4; i++) span[5 + i] = chars[b[4 + i] % chars.Length];
            span[9] = '-';
            for (var i = 0; i < 4; i++) span[10 + i] = chars[b[8 + i] % chars.Length];
        });
    }
}
