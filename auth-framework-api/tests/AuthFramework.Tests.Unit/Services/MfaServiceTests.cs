using Xunit;
using AuthFramework.Application.DTOs.Mfa;
using AuthFramework.Application.Interfaces;
using AuthFramework.Application.Services;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using FluentAssertions;
using Microsoft.Extensions.Logging;
using Moq;

namespace AuthFramework.Tests.Unit.Services;

public sealed class MfaServiceTests
{
    private readonly Mock<IRepository<MfaDevice>> _deviceRepo = new();
    private readonly Mock<IRepository<MfaChallenge>> _challengeRepo = new();
    private readonly Mock<IRepository<MfaRecoveryCode>> _recoveryRepo = new();
    private readonly Mock<IEncryptionService> _encryption = new();
    private readonly Mock<ILogger<MfaService>> _logger = new();

    private MfaService CreateSut() => new(
        _deviceRepo.Object,
        _challengeRepo.Object,
        _recoveryRepo.Object,
        _encryption.Object,
        _logger.Object);

    [Fact]
    public async Task EnrollDeviceAsync_Totp_ReturnSecretAndQrCodeUri()
    {
        // Arrange
        var userId = Guid.NewGuid();
        var tenantId = Guid.NewGuid();
        _encryption.Setup(e => e.Encrypt(It.IsAny<string>())).Returns("encrypted-secret");
        _deviceRepo.Setup(r => r.AddAsync(It.IsAny<MfaDevice>(), default))
            .ReturnsAsync((MfaDevice d, CancellationToken _) => d);

        var sut = CreateSut();

        // Act
        var result = await sut.EnrollDeviceAsync(userId, tenantId, new EnrollMfaRequest
        {
            MethodType = MfaMethodType.Totp,
            DeviceName = "My Authenticator",
        });

        // Assert
        result.Should().NotBeNull();
        result.DeviceId.Should().NotBeEmpty();
        result.MethodType.Should().Be(MfaMethodType.Totp);
        result.Secret.Should().NotBeNullOrEmpty();
        result.QrCodeUri.Should().StartWith("otpauth://totp/");
    }

    [Fact]
    public async Task EnrollDeviceAsync_Sms_DoesNotGenerateSecret()
    {
        // Arrange
        var userId = Guid.NewGuid();
        var tenantId = Guid.NewGuid();
        _encryption.Setup(e => e.Encrypt(It.IsAny<string>())).Returns("encrypted-phone");
        _deviceRepo.Setup(r => r.AddAsync(It.IsAny<MfaDevice>(), default))
            .ReturnsAsync((MfaDevice d, CancellationToken _) => d);

        var sut = CreateSut();

        // Act
        var result = await sut.EnrollDeviceAsync(userId, tenantId, new EnrollMfaRequest
        {
            MethodType = MfaMethodType.Sms,
            PhoneNumber = "+15555555555",
        });

        // Assert
        result.Secret.Should().BeNull();
        result.QrCodeUri.Should().BeNull();
        result.MethodType.Should().Be(MfaMethodType.Sms);
    }

    [Fact]
    public async Task GetDevicesAsync_ReturnsOnlyActiveDevices()
    {
        var userId = Guid.NewGuid();
        var tenantId = Guid.NewGuid();
        var devices = new List<MfaDevice>
        {
            new() { Id = Guid.NewGuid(), UserId = userId, TenantId = tenantId, MethodType = MfaMethodType.Totp, IsActive = true, IsVerified = true, CreatedAt = DateTimeOffset.UtcNow },
        };

        _deviceRepo.Setup(r => r.FindAsync(It.IsAny<System.Linq.Expressions.Expression<Func<MfaDevice, bool>>>(), 1, 100, default))
            .ReturnsAsync(AuthFramework.Core.Models.PagedResult<MfaDevice>.Create(devices, 1, 1, 100));

        var sut = CreateSut();
        var result = await sut.GetDevicesAsync(userId, tenantId);

        result.Should().HaveCount(1);
        result[0].MethodType.Should().Be(MfaMethodType.Totp);
        result[0].IsVerified.Should().BeTrue();
    }
}
