using AuthFramework.Application.DTOs.OAuth;
using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Entities;
using AuthFramework.Shared.Exceptions;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Logging;
using System.Security.Cryptography;

namespace AuthFramework.Application.Services;

/// <summary>OAuth 2.0 authorization server implementation.</summary>
public sealed class OAuthService : IOAuthService
{
    private readonly IRepository<OAuthApplication> _appRepository;
    private readonly IRepository<OAuthAuthorizationCode> _codeRepository;
    private readonly IRepository<OAuthToken> _tokenRepository;
    private readonly IUserRepository _userRepository;
    private readonly ITokenService _tokenService;
    private readonly ILogger<OAuthService> _logger;

    public OAuthService(
        IRepository<OAuthApplication> appRepository,
        IRepository<OAuthAuthorizationCode> codeRepository,
        IRepository<OAuthToken> tokenRepository,
        IUserRepository userRepository,
        ITokenService tokenService,
        ILogger<OAuthService> logger)
    {
        _appRepository = appRepository;
        _codeRepository = codeRepository;
        _tokenRepository = tokenRepository;
        _userRepository = userRepository;
        _tokenService = tokenService;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<OAuthApplicationDto> CreateApplicationAsync(Guid tenantId, CreateApplicationRequest request, CancellationToken cancellationToken = default)
    {
        var clientId = GenerateClientId();
        var clientSecret = GenerateClientSecret();

        var app = new OAuthApplication
        {
            Id = UuidV7Generator.NewGuid(),
            TenantId = tenantId,
            Name = request.Name,
            ClientId = clientId,
            ClientSecretHash = BCrypt.Net.BCrypt.HashPassword(clientSecret, AuthConstants.BcryptWorkFactor),
            ApplicationType = request.ApplicationType,
            RedirectUris = request.RedirectUris,
            AllowedScopes = request.AllowedScopes,
            IsActive = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        await _appRepository.AddAsync(app, cancellationToken);
        _logger.LogInformation("OAuth application {AppId} created in tenant {TenantId}", app.Id, tenantId);

        return new OAuthApplicationDto
        {
            Id = app.Id,
            Name = app.Name,
            ClientId = app.ClientId,
            ClientSecret = clientSecret, // returned once on creation
            ApplicationType = app.ApplicationType,
            RedirectUris = app.RedirectUris,
            IsActive = app.IsActive,
        };
    }

    /// <inheritdoc/>
    public async Task<OAuthApplicationDto?> GetApplicationAsync(Guid applicationId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var app = await _appRepository.GetByIdAsync(applicationId, cancellationToken);
        if (app is null || app.TenantId != tenantId) return null;

        return new OAuthApplicationDto
        {
            Id = app.Id,
            Name = app.Name,
            ClientId = app.ClientId,
            ApplicationType = app.ApplicationType,
            RedirectUris = app.RedirectUris,
            IsActive = app.IsActive,
        };
    }

    /// <inheritdoc/>
    public async Task<string> AuthorizeAsync(Guid userId, Guid tenantId, AuthorizeRequest request, CancellationToken cancellationToken = default)
    {
        var apps = await _appRepository.FindAsync(
            a => a.ClientId == request.ClientId && a.TenantId == tenantId && a.IsActive,
            cancellationToken: cancellationToken);

        var app = apps.Items.FirstOrDefault()
            ?? throw new AuthFrameworkException("OAuth client not found or inactive.");

        if (!app.RedirectUris.Contains(request.RedirectUri))
            throw new AuthFrameworkException("Invalid redirect URI.");

        var rawCode = GenerateAuthCode();
        var code = new OAuthAuthorizationCode
        {
            Id = UuidV7Generator.NewGuid(),
            ApplicationId = app.Id,
            UserId = userId,
            TenantId = tenantId,
            Code = rawCode,
            RedirectUri = request.RedirectUri,
            Scopes = (request.Scope ?? string.Empty).Split(' ', StringSplitOptions.RemoveEmptyEntries),
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(10),
            CreatedAt = DateTimeOffset.UtcNow,
        };

        await _codeRepository.AddAsync(code, cancellationToken);
        return rawCode;
    }

    /// <inheritdoc/>
    public async Task<TokenResponse> ExchangeCodeAsync(TokenRequest request, CancellationToken cancellationToken = default)
    {
        if (request.GrantType != "authorization_code")
            throw new AuthFrameworkException($"Unsupported grant type: {request.GrantType}");

        var codes = await _codeRepository.FindAsync(
            c => c.Code == request.Code && c.UsedAt == null && c.ExpiresAt > DateTimeOffset.UtcNow,
            cancellationToken: cancellationToken);

        var code = codes.Items.FirstOrDefault()
            ?? throw new InvalidTokenException("Authorization code is invalid or expired.");

        var app = await _appRepository.GetByIdAsync(code.ApplicationId, cancellationToken)
            ?? throw new AuthFrameworkException("Application not found.");

        if (app.ClientId != request.ClientId)
            throw new AuthFrameworkException("Client ID mismatch.");

        if (request.ClientSecret != null && !BCrypt.Net.BCrypt.Verify(request.ClientSecret, app.ClientSecretHash ?? ""))
            throw new AuthFrameworkException("Invalid client credentials.");

        if (request.RedirectUri != null && code.RedirectUri != request.RedirectUri)
            throw new AuthFrameworkException("Redirect URI mismatch.");

        var user = await _userRepository.GetByIdAsync(code.UserId, cancellationToken)
            ?? throw new UserNotFoundException(code.UserId);

        var dummySessionId = UuidV7Generator.NewGuid();
        var accessToken = _tokenService.GenerateAccessToken(user, dummySessionId, code.Scopes);
        var refreshToken = _tokenService.GenerateRefreshToken();

        var token = new OAuthToken
        {
            Id = UuidV7Generator.NewGuid(),
            ApplicationId = app.Id,
            UserId = user.Id,
            TenantId = code.TenantId,
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            Scopes = code.Scopes,
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(AuthConstants.DefaultAccessTokenExpiryMinutes),
            RefreshExpiresAt = DateTimeOffset.UtcNow.AddDays(AuthConstants.DefaultRefreshTokenExpiryDays),
            CreatedAt = DateTimeOffset.UtcNow,
        };

        await _tokenRepository.AddAsync(token, cancellationToken);

        code.UsedAt = DateTimeOffset.UtcNow;
        await _codeRepository.UpdateAsync(code, cancellationToken);

        return new TokenResponse
        {
            AccessToken = accessToken,
            RefreshToken = refreshToken,
            ExpiresIn = AuthConstants.DefaultAccessTokenExpiryMinutes * 60,
            TokenType = "Bearer",
            Scope = string.Join(" ", code.Scopes),
        };
    }

    /// <inheritdoc/>
    public async Task RevokeTokenAsync(string tokenValue, string? tokenTypeHint, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var tokens = await _tokenRepository.FindAsync(
            t => (t.AccessToken == tokenValue || t.RefreshToken == tokenValue) && t.TenantId == tenantId && t.RevokedAt == null,
            cancellationToken: cancellationToken);

        foreach (var token in tokens.Items)
        {
            token.RevokedAt = DateTimeOffset.UtcNow;
            await _tokenRepository.UpdateAsync(token, cancellationToken);
        }
    }

    /// <inheritdoc/>
    public async Task<TokenIntrospectionResponse> IntrospectTokenAsync(string tokenValue, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var tokens = await _tokenRepository.FindAsync(
            t => t.AccessToken == tokenValue && t.TenantId == tenantId && t.RevokedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow,
            cancellationToken: cancellationToken);

        var token = tokens.Items.FirstOrDefault();
        if (token is null)
            return new TokenIntrospectionResponse { Active = false };

        var app = await _appRepository.GetByIdAsync(token.ApplicationId, cancellationToken);

        return new TokenIntrospectionResponse
        {
            Active = true,
            Sub = token.UserId?.ToString(),
            Exp = token.ExpiresAt.ToUnixTimeSeconds(),
            Scope = string.Join(" ", token.Scopes),
            ClientId = app?.ClientId,
        };
    }

    private static string GenerateClientId() => $"client_{Convert.ToHexString(RandomNumberGenerator.GetBytes(8)).ToLowerInvariant()}";
    private static string GenerateClientSecret() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
    private static string GenerateAuthCode() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
