using Xunit;
using AuthFramework.Application.DTOs.Auth;
using AuthFramework.Application.Interfaces;
using AuthFramework.Application.Services;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Core.Models;
using AuthFramework.Shared.Exceptions;
using FluentAssertions;
using Microsoft.Extensions.Logging;
using Moq;

namespace AuthFramework.Tests.Unit.Services;

public sealed class AuthenticationServiceTests
{
    private readonly Mock<IUserRepository> _userRepo = new();
    private readonly Mock<ITenantRepository> _tenantRepo = new();
    private readonly Mock<IRepository<UserCredential>> _credentialRepo = new();
    private readonly Mock<IRepository<UserProfile>> _profileRepo = new();
    private readonly Mock<IRepository<PasswordResetToken>> _resetTokenRepo = new();
    private readonly Mock<IRepository<EmailVerificationToken>> _emailTokenRepo = new();
    private readonly Mock<ISessionService> _sessionService = new();
    private readonly Mock<ITokenService> _tokenService = new();
    private readonly Mock<IEncryptionService> _encryptionService = new();
    private readonly Mock<IAuditService> _auditService = new();
    private readonly Mock<ILogger<AuthenticationService>> _logger = new();

    private AuthenticationService CreateSut() => new(
        _userRepo.Object,
        _tenantRepo.Object,
        _credentialRepo.Object,
        _profileRepo.Object,
        _resetTokenRepo.Object,
        _emailTokenRepo.Object,
        _sessionService.Object,
        _tokenService.Object,
        _encryptionService.Object,
        _auditService.Object,
        _logger.Object);

    private static Tenant ActiveTenant(Guid tenantId) => new()
    {
        Id = tenantId,
        Name = "Test Tenant",
        Slug = "test",
        Status = TenantStatus.Active,
    };

    private static User ActiveUser(Guid userId, Guid tenantId, string emailHash) => new()
    {
        Id = userId,
        TenantId = tenantId,
        Email = "user@example.com",
        EmailHash = emailHash,
        Status = UserStatus.Active,
        IsEmailVerified = true,
    };

    #region RegisterAsync

    [Fact]
    public async Task RegisterAsync_WithValidRequest_CreatesUserAndReturnsTokens()
    {
        // Arrange
        var tenantId = Guid.NewGuid();
        var emailHash = "emailhash123";

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default)).ReturnsAsync((User?)null);
        _userRepo.Setup(r => r.AddAsync(It.IsAny<User>(), default)).ReturnsAsync((User u, CancellationToken _) => u);
        _credentialRepo.Setup(r => r.AddAsync(It.IsAny<UserCredential>(), default)).ReturnsAsync((UserCredential c, CancellationToken _) => c);
        _profileRepo.Setup(r => r.AddAsync(It.IsAny<UserProfile>(), default)).ReturnsAsync((UserProfile p, CancellationToken _) => p);
        _emailTokenRepo.Setup(r => r.AddAsync(It.IsAny<EmailVerificationToken>(), default)).ReturnsAsync((EmailVerificationToken t, CancellationToken _) => t);
        _encryptionService.Setup(e => e.Encrypt(It.IsAny<string>())).Returns("encrypted");
        _sessionService.Setup(s => s.CreateSessionAsync(It.IsAny<Guid>(), tenantId, null, null, null, false, default))
            .ReturnsAsync(new UserSession { Id = Guid.NewGuid() });
        _tokenService.Setup(t => t.GenerateAccessToken(It.IsAny<User>(), It.IsAny<Guid>(), null)).Returns("access-token");
        _tokenService.Setup(t => t.GenerateRefreshToken()).Returns("refresh-token");

        var sut = CreateSut();
        var request = new RegisterRequest
        {
            Email = "user@example.com",
            Password = "P@ssw0rd!123",
            FirstName = "Jane",
            LastName = "Doe",
            TenantId = tenantId,
        };

        // Act
        var result = await sut.RegisterAsync(request);

        // Assert
        result.Should().NotBeNull();
        result.AccessToken.Should().Be("access-token");
        result.RefreshToken.Should().Be("refresh-token");
        result.MfaRequired.Should().BeFalse();
        _userRepo.Verify(r => r.AddAsync(It.Is<User>(u => u.TenantId == tenantId), default), Times.Once);
    }

    [Fact]
    public async Task RegisterAsync_WithDuplicateEmail_ThrowsAuthFrameworkException()
    {
        // Arrange
        var tenantId = Guid.NewGuid();
        var emailHash = "existinghash";

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default))
            .ReturnsAsync(new User { Id = Guid.NewGuid() });

        var sut = CreateSut();

        // Act & Assert
        await sut.Invoking(s => s.RegisterAsync(new RegisterRequest
        {
            Email = "dup@example.com",
            Password = "P@ssw0rd!123",
            TenantId = tenantId,
        })).Should().ThrowAsync<AuthFrameworkException>();
    }

    [Fact]
    public async Task RegisterAsync_WithInvalidPassword_ThrowsValidationException()
    {
        // Arrange
        var tenantId = Guid.NewGuid();
        var emailHash = "newhash";

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default)).ReturnsAsync((User?)null);

        var sut = CreateSut();

        // Act & Assert
        await sut.Invoking(s => s.RegisterAsync(new RegisterRequest
        {
            Email = "new@example.com",
            Password = "weak",    // too short, no uppercase, no digit, no special
            TenantId = tenantId,
        })).Should().ThrowAsync<Shared.Exceptions.ValidationException>();
    }

    [Fact]
    public async Task RegisterAsync_WithUnknownTenant_ThrowsTenantNotFoundException()
    {
        var tenantId = Guid.NewGuid();
        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync((Tenant?)null);

        var sut = CreateSut();

        await sut.Invoking(s => s.RegisterAsync(new RegisterRequest
        {
            Email = "user@example.com",
            Password = "P@ssw0rd!123",
            TenantId = tenantId,
        })).Should().ThrowAsync<TenantNotFoundException>();
    }

    #endregion

    #region LoginAsync

    [Fact]
    public async Task LoginAsync_WithValidCredentials_ReturnsTokens()
    {
        // Arrange
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var emailHash = "hash";
        var password = "P@ssw0rd!123";
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(password, 4);

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default)).ReturnsAsync(ActiveUser(userId, tenantId, emailHash));
        _credentialRepo.Setup(r => r.FindAsync(It.IsAny<System.Linq.Expressions.Expression<Func<UserCredential, bool>>>(), 1, 20, default))
            .ReturnsAsync(PagedResult<UserCredential>.Create(
                [new UserCredential { Id = Guid.NewGuid(), UserId = userId, PasswordHash = passwordHash }],
                1, 1, 20));
        _userRepo.Setup(r => r.ResetFailedLoginAttemptsAsync(userId, default)).Returns(Task.CompletedTask);
        _userRepo.Setup(r => r.UpdateAsync(It.IsAny<User>(), default)).Returns(Task.CompletedTask);
        _credentialRepo.Setup(r => r.ExistsAsync(It.IsAny<System.Linq.Expressions.Expression<Func<UserCredential, bool>>>(), default)).ReturnsAsync(false);
        _sessionService.Setup(s => s.CreateSessionAsync(userId, tenantId, null, It.IsAny<string>(), It.IsAny<string>(), false, default))
            .ReturnsAsync(new UserSession { Id = Guid.NewGuid() });
        _tokenService.Setup(t => t.GenerateAccessToken(It.IsAny<User>(), It.IsAny<Guid>(), null)).Returns("access-token");
        _tokenService.Setup(t => t.GenerateRefreshToken()).Returns("refresh-token");

        var sut = CreateSut();

        // Act
        var result = await sut.LoginAsync(new LoginRequest
        {
            Email = "user@example.com",
            Password = password,
            TenantId = tenantId,
        });

        // Assert
        result.AccessToken.Should().Be("access-token");
        result.MfaRequired.Should().BeFalse();
    }

    [Fact]
    public async Task LoginAsync_WithWrongPassword_ThrowsAuthenticationException()
    {
        // Arrange
        var tenantId = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var emailHash = "hash";
        var passwordHash = BCrypt.Net.BCrypt.HashPassword("correct-password", 4);

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default)).ReturnsAsync(ActiveUser(userId, tenantId, emailHash));
        _credentialRepo.Setup(r => r.FindAsync(It.IsAny<System.Linq.Expressions.Expression<Func<UserCredential, bool>>>(), 1, 20, default))
            .ReturnsAsync(PagedResult<UserCredential>.Create(
                [new UserCredential { Id = Guid.NewGuid(), UserId = userId, PasswordHash = passwordHash }],
                1, 1, 20));
        _userRepo.Setup(r => r.IncrementFailedLoginAttemptsAsync(userId, default)).Returns(Task.CompletedTask);

        var sut = CreateSut();

        // Act & Assert
        await sut.Invoking(s => s.LoginAsync(new LoginRequest
        {
            Email = "user@example.com",
            Password = "wrong-password",
            TenantId = tenantId,
        })).Should().ThrowAsync<AuthenticationException>();

        _userRepo.Verify(r => r.IncrementFailedLoginAttemptsAsync(userId, default), Times.Once);
    }

    [Fact]
    public async Task LoginAsync_WithLockedAccount_ThrowsAccountLockedException()
    {
        var tenantId = Guid.NewGuid();
        var emailHash = "hash";
        var user = new User
        {
            Id = Guid.NewGuid(),
            TenantId = tenantId,
            Email = "user@example.com",
            EmailHash = emailHash,
            Status = UserStatus.Active,
            LockedUntil = DateTimeOffset.UtcNow.AddMinutes(10),
        };

        _tenantRepo.Setup(r => r.GetByIdAsync(tenantId, default)).ReturnsAsync(ActiveTenant(tenantId));
        _encryptionService.Setup(e => e.Hash(It.IsAny<string>())).Returns(emailHash);
        _userRepo.Setup(r => r.FindByEmailHashAsync(emailHash, tenantId, default)).ReturnsAsync(user);

        var sut = CreateSut();

        await sut.Invoking(s => s.LoginAsync(new LoginRequest
        {
            Email = "user@example.com",
            Password = "any",
            TenantId = tenantId,
        })).Should().ThrowAsync<AccountLockedException>();
    }

    #endregion
}
