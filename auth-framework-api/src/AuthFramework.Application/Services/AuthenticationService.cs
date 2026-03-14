using AuthFramework.Application.DTOs.Auth;
using AuthFramework.Application.DTOs.Users;
using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Shared.Exceptions;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Logging;

namespace AuthFramework.Application.Services;

/// <summary>Handles user registration, authentication, and credential management.</summary>
public sealed class AuthenticationService : IAuthenticationService
{
    private readonly IUserRepository _userRepository;
    private readonly ITenantRepository _tenantRepository;
    private readonly IRepository<UserCredential> _credentialRepository;
    private readonly IRepository<UserProfile> _profileRepository;
    private readonly IRepository<PasswordResetToken> _passwordResetRepository;
    private readonly IRepository<EmailVerificationToken> _emailVerificationRepository;
    private readonly ISessionService _sessionService;
    private readonly ITokenService _tokenService;
    private readonly IEncryptionService _encryptionService;
    private readonly IAuditService _auditService;
    private readonly ILogger<AuthenticationService> _logger;

    public AuthenticationService(
        IUserRepository userRepository,
        ITenantRepository tenantRepository,
        IRepository<UserCredential> credentialRepository,
        IRepository<UserProfile> profileRepository,
        IRepository<PasswordResetToken> passwordResetRepository,
        IRepository<EmailVerificationToken> emailVerificationRepository,
        ISessionService sessionService,
        ITokenService tokenService,
        IEncryptionService encryptionService,
        IAuditService auditService,
        ILogger<AuthenticationService> logger)
    {
        _userRepository = userRepository;
        _tenantRepository = tenantRepository;
        _credentialRepository = credentialRepository;
        _profileRepository = profileRepository;
        _passwordResetRepository = passwordResetRepository;
        _emailVerificationRepository = emailVerificationRepository;
        _sessionService = sessionService;
        _tokenService = tokenService;
        _encryptionService = encryptionService;
        _auditService = auditService;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<LoginResponse> RegisterAsync(RegisterRequest request, CancellationToken cancellationToken = default)
    {
        var tenant = await _tenantRepository.GetByIdAsync(request.TenantId, cancellationToken)
            ?? throw new TenantNotFoundException(request.TenantId);

        if (tenant.Status != TenantStatus.Active)
            throw new AuthFrameworkException("Tenant is not active.");

        PasswordValidator.Validate(request.Password);

        var emailHash = _encryptionService.Hash(request.Email);
        var existingUser = await _userRepository.FindByEmailHashAsync(emailHash, request.TenantId, cancellationToken);
        if (existingUser != null)
            throw new AuthFrameworkException("An account with this email address already exists.");

        var now = DateTimeOffset.UtcNow;
        var userId = UuidV7Generator.NewGuid();

        var user = new User
        {
            Id = userId,
            TenantId = request.TenantId,
            Email = request.Email.ToLowerInvariant(),
            EmailHash = emailHash,
            Status = UserStatus.PendingVerification,
            IsEmailVerified = false,
            CreatedAt = now,
            UpdatedAt = now,
        };

        await _userRepository.AddAsync(user, cancellationToken);

        var credential = new UserCredential
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = request.TenantId,
            CredentialType = CredentialType.Password,
            PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.Password, AuthConstants.BcryptWorkFactor),
            CreatedAt = now,
            UpdatedAt = now,
        };

        await _credentialRepository.AddAsync(credential, cancellationToken);

        var profile = new UserProfile
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = request.TenantId,
            FirstName = request.FirstName != null ? _encryptionService.Encrypt(request.FirstName) : null,
            LastName = request.LastName != null ? _encryptionService.Encrypt(request.LastName) : null,
            Locale = request.Language,
            Timezone = request.Timezone,
            CreatedAt = now,
            UpdatedAt = now,
        };

        await _profileRepository.AddAsync(profile, cancellationToken);

        var verificationToken = new EmailVerificationToken
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = request.TenantId,
            Email = request.Email.ToLowerInvariant(),
            TokenHash = _encryptionService.Hash(Guid.NewGuid().ToString()),
            ExpiresAt = now.AddHours(AuthConstants.EmailVerificationTokenExpiryHours),
            CreatedAt = now,
        };

        await _emailVerificationRepository.AddAsync(verificationToken, cancellationToken);

        await _auditService.LogEventAsync(
            request.TenantId, AuditEventType.UserManagement,
            "register", "success", userId, "User", userId.ToString(),
            cancellationToken: cancellationToken);

        _logger.LogInformation("User {UserId} registered in tenant {TenantId}", userId, request.TenantId);

        var session = await _sessionService.CreateSessionAsync(userId, request.TenantId, null, null, null, false, cancellationToken);
        var accessToken = _tokenService.GenerateAccessToken(user, session.Id);
        var refreshToken = _tokenService.GenerateRefreshToken();

        return new LoginResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = AuthConstants.DefaultAccessTokenExpiryMinutes * 60,
            TokenType = "Bearer",
            MfaRequired = false,
            User = MapToUserDto(user, null),
        };
    }

    /// <inheritdoc/>
    public async Task<LoginResponse> LoginAsync(LoginRequest request, string? ipAddress = null, string? userAgent = null, CancellationToken cancellationToken = default)
    {
        var tenant = await _tenantRepository.GetByIdAsync(request.TenantId, cancellationToken)
            ?? throw new TenantNotFoundException(request.TenantId);

        if (tenant.Status != TenantStatus.Active)
            throw new AuthFrameworkException("Tenant is not active.");

        var emailHash = _encryptionService.Hash(request.Email);
        var user = await _userRepository.FindByEmailHashAsync(emailHash, request.TenantId, cancellationToken);

        if (user is null)
        {
            await _auditService.LogEventAsync(request.TenantId, AuditEventType.Authentication,
                "login", "failure", null, "User", null, ipAddress, userAgent, cancellationToken: cancellationToken);
            throw new AuthenticationException("Invalid email or password.");
        }

        if (user.LockedUntil.HasValue && user.LockedUntil.Value > DateTimeOffset.UtcNow)
            throw new AccountLockedException(user.LockedUntil.Value);

        if (user.Status == UserStatus.Deleted || user.Status == UserStatus.Suspended)
            throw new AuthenticationException("Account is not accessible.");

        var credentials = await _credentialRepository.FindAsync(
            c => c.UserId == user.Id && c.CredentialType == CredentialType.Password,
            cancellationToken: cancellationToken);

        var credential = credentials.Items.FirstOrDefault();

        if (credential?.PasswordHash is null || !BCrypt.Net.BCrypt.Verify(request.Password, credential.PasswordHash))
        {
            await _userRepository.IncrementFailedLoginAttemptsAsync(user.Id, cancellationToken);
            await _auditService.LogEventAsync(request.TenantId, AuditEventType.Authentication,
                "login", "failure", user.Id, "User", user.Id.ToString(), ipAddress, userAgent, cancellationToken: cancellationToken);
            throw new AuthenticationException("Invalid email or password.");
        }

        await _userRepository.ResetFailedLoginAttemptsAsync(user.Id, cancellationToken);

        user.LastLoginAt = DateTimeOffset.UtcNow;
        await _userRepository.UpdateAsync(user, cancellationToken);

        var hasMfaDevices = await _credentialRepository.ExistsAsync(
            _ => false, cancellationToken); // placeholder - real impl checks MFA devices

        if (tenant.RequireMfa)
        {
            // In a full implementation, create an MFA challenge here
            await _auditService.LogEventAsync(request.TenantId, AuditEventType.Authentication,
                "login_mfa_required", "pending", user.Id, "User", user.Id.ToString(), ipAddress, userAgent, cancellationToken: cancellationToken);
            return new LoginResponse { MfaRequired = true };
        }

        var session = await _sessionService.CreateSessionAsync(user.Id, request.TenantId, null, ipAddress, userAgent, false, cancellationToken);
        var accessToken = _tokenService.GenerateAccessToken(user, session.Id);
        var refreshToken = _tokenService.GenerateRefreshToken();

        await _auditService.LogEventAsync(request.TenantId, AuditEventType.Authentication,
            "login", "success", user.Id, "User", user.Id.ToString(), ipAddress, userAgent, cancellationToken: cancellationToken);

        _logger.LogInformation("User {UserId} logged in to tenant {TenantId}", user.Id, request.TenantId);

        return new LoginResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = AuthConstants.DefaultAccessTokenExpiryMinutes * 60,
            TokenType = "Bearer",
            User = MapToUserDto(user, null),
        };
    }

    /// <inheritdoc/>
    public async Task LogoutAsync(Guid userId, Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessionService.GetSessionAsync(sessionId, cancellationToken);
        if (session is null) return;

        await _sessionService.RevokeSessionAsync(sessionId, cancellationToken);
        await _auditService.LogEventAsync(session.TenantId, AuditEventType.Authentication,
            "logout", "success", userId, "Session", sessionId.ToString(), cancellationToken: cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<LoginResponse> RefreshTokenAsync(RefreshTokenRequest request, CancellationToken cancellationToken = default)
    {
        // In a full implementation, look up the refresh token from storage and validate it.
        // This stub returns an error to indicate a token was not found.
        await Task.CompletedTask;
        throw new InvalidTokenException("Refresh token not found or expired.");
    }

    /// <inheritdoc/>
    public async Task ChangePasswordAsync(Guid userId, Guid tenantId, ChangePasswordRequest request, CancellationToken cancellationToken = default)
    {
        var user = await _userRepository.GetByIdAsync(userId, cancellationToken)
            ?? throw new UserNotFoundException(userId);

        var credentials = await _credentialRepository.FindAsync(
            c => c.UserId == userId && c.CredentialType == CredentialType.Password,
            cancellationToken: cancellationToken);

        var credential = credentials.Items.FirstOrDefault()
            ?? throw new AuthenticationException("No password credential found.");

        if (!BCrypt.Net.BCrypt.Verify(request.CurrentPassword, credential.PasswordHash!))
            throw new AuthenticationException("Current password is incorrect.");

        PasswordValidator.Validate(request.NewPassword);

        credential.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, AuthConstants.BcryptWorkFactor);
        credential.UpdatedAt = DateTimeOffset.UtcNow;
        await _credentialRepository.UpdateAsync(credential, cancellationToken);

        await _sessionService.RevokeAllSessionsAsync(userId, tenantId, cancellationToken: cancellationToken);

        await _auditService.LogEventAsync(tenantId, AuditEventType.UserManagement,
            "password_change", "success", userId, "User", userId.ToString(), cancellationToken: cancellationToken);

        _logger.LogInformation("User {UserId} changed their password", userId);
    }

    /// <inheritdoc/>
    public async Task RequestPasswordResetAsync(PasswordResetRequest request, CancellationToken cancellationToken = default)
    {
        var emailHash = _encryptionService.Hash(request.Email);
        var user = await _userRepository.FindByEmailHashAsync(emailHash, request.TenantId, cancellationToken);

        // Always return success to prevent email enumeration
        if (user is null) return;

        var rawToken = Convert.ToBase64String(Guid.NewGuid().ToByteArray());
        var resetToken = new PasswordResetToken
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = user.Id,
            TenantId = request.TenantId,
            TokenHash = _encryptionService.Hash(rawToken),
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(AuthConstants.PasswordResetTokenExpiryMinutes),
            CreatedAt = DateTimeOffset.UtcNow,
        };

        await _passwordResetRepository.AddAsync(resetToken, cancellationToken);

        // TODO: Dispatch password reset email via IEmailService
        _logger.LogInformation("Password reset requested for user {UserId}", user.Id);
    }

    /// <inheritdoc/>
    public async Task ResetPasswordAsync(ResetPasswordRequest request, CancellationToken cancellationToken = default)
    {
        var tokenHash = _encryptionService.Hash(request.Token);
        var tokens = await _passwordResetRepository.FindAsync(
            t => t.TenantId == request.TenantId && t.TokenHash == tokenHash && t.UsedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow,
            cancellationToken: cancellationToken);

        var token = tokens.Items.FirstOrDefault()
            ?? throw new InvalidTokenException("Password reset token is invalid or expired.");

        PasswordValidator.Validate(request.NewPassword);

        var credentials = await _credentialRepository.FindAsync(
            c => c.UserId == token.UserId && c.CredentialType == CredentialType.Password,
            cancellationToken: cancellationToken);

        var credential = credentials.Items.FirstOrDefault();
        if (credential is null)
        {
            credential = new UserCredential
            {
                Id = UuidV7Generator.NewGuid(),
                UserId = token.UserId,
                TenantId = request.TenantId,
                CredentialType = CredentialType.Password,
                CreatedAt = DateTimeOffset.UtcNow,
                UpdatedAt = DateTimeOffset.UtcNow,
            };
            credential.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, AuthConstants.BcryptWorkFactor);
            await _credentialRepository.AddAsync(credential, cancellationToken);
        }
        else
        {
            credential.PasswordHash = BCrypt.Net.BCrypt.HashPassword(request.NewPassword, AuthConstants.BcryptWorkFactor);
            credential.UpdatedAt = DateTimeOffset.UtcNow;
            await _credentialRepository.UpdateAsync(credential, cancellationToken);
        }

        token.UsedAt = DateTimeOffset.UtcNow;
        await _passwordResetRepository.UpdateAsync(token, cancellationToken);

        await _sessionService.RevokeAllSessionsAsync(token.UserId, request.TenantId, cancellationToken: cancellationToken);

        _logger.LogInformation("Password reset completed for user {UserId}", token.UserId);
    }

    /// <inheritdoc/>
    public async Task VerifyEmailAsync(string tokenValue, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var tokenHash = _encryptionService.Hash(tokenValue);
        var tokens = await _emailVerificationRepository.FindAsync(
            t => t.TenantId == tenantId && t.TokenHash == tokenHash && t.UsedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow,
            cancellationToken: cancellationToken);

        var token = tokens.Items.FirstOrDefault()
            ?? throw new InvalidTokenException("Email verification token is invalid or expired.");

        var user = await _userRepository.GetByIdAsync(token.UserId, cancellationToken)
            ?? throw new UserNotFoundException(token.UserId);

        user.IsEmailVerified = true;
        if (user.Status == UserStatus.PendingVerification)
            user.Status = UserStatus.Active;
        user.UpdatedAt = DateTimeOffset.UtcNow;

        await _userRepository.UpdateAsync(user, cancellationToken);

        token.UsedAt = DateTimeOffset.UtcNow;
        await _emailVerificationRepository.UpdateAsync(token, cancellationToken);

        await _auditService.LogEventAsync(tenantId, AuditEventType.UserManagement,
            "email_verified", "success", user.Id, "User", user.Id.ToString(), cancellationToken: cancellationToken);

        _logger.LogInformation("Email verified for user {UserId}", user.Id);
    }

    private static UserDto MapToUserDto(User user, UserProfile? profile) => new()
    {
        Id = user.Id,
        Email = user.Email,
        FirstName = profile?.FirstName,
        LastName = profile?.LastName,
        DisplayName = profile?.DisplayName,
        Status = user.Status,
        IsEmailVerified = user.IsEmailVerified,
        CreatedAt = user.CreatedAt,
    };
}
