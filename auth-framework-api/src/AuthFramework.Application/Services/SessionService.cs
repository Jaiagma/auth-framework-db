using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Models;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace AuthFramework.Application.Services;

/// <summary>Manages user session lifecycle in the database.</summary>
public sealed class SessionService : ISessionService
{
    private readonly IRepository<UserSession> _sessionRepository;
    private readonly IConfiguration _configuration;
    private readonly ILogger<SessionService> _logger;

    public SessionService(
        IRepository<UserSession> sessionRepository,
        IConfiguration configuration,
        ILogger<SessionService> logger)
    {
        _sessionRepository = sessionRepository;
        _configuration = configuration;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<UserSession> CreateSessionAsync(
        Guid userId,
        Guid tenantId,
        Guid? applicationId,
        string? ipAddress,
        string? userAgent,
        bool mfaVerified = false,
        CancellationToken cancellationToken = default)
    {
        var lifetimeSec = int.TryParse(_configuration["SessionSettings:LifetimeSec"], out var sec)
            ? sec : AuthConstants.DefaultAccessTokenExpiryMinutes * 60;

        var session = new UserSession
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = tenantId,
            ApplicationId = applicationId,
            IpAddress = ipAddress,
            UserAgent = userAgent,
            MfaVerified = mfaVerified,
            ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(lifetimeSec),
            LastActivityAt = DateTimeOffset.UtcNow,
            CreatedAt = DateTimeOffset.UtcNow,
        };

        return await _sessionRepository.AddAsync(session, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<bool> ValidateSessionAsync(Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessionRepository.GetByIdAsync(sessionId, cancellationToken);
        return session is not null
            && session.RevokedAt is null
            && session.ExpiresAt > DateTimeOffset.UtcNow;
    }

    /// <inheritdoc/>
    public async Task<UserSession?> GetSessionAsync(Guid sessionId, CancellationToken cancellationToken = default)
        => await _sessionRepository.GetByIdAsync(sessionId, cancellationToken);

    /// <inheritdoc/>
    public async Task<PagedResult<UserSession>> ListSessionsAsync(
        Guid userId,
        Guid tenantId,
        int page = 1,
        int pageSize = 20,
        CancellationToken cancellationToken = default)
        => await _sessionRepository.FindAsync(
            s => s.UserId == userId && s.TenantId == tenantId && s.RevokedAt == null && s.ExpiresAt > DateTimeOffset.UtcNow,
            page, pageSize, cancellationToken);

    /// <inheritdoc/>
    public async Task RevokeSessionAsync(Guid sessionId, CancellationToken cancellationToken = default)
    {
        var session = await _sessionRepository.GetByIdAsync(sessionId, cancellationToken);
        if (session is null) return;

        session.RevokedAt = DateTimeOffset.UtcNow;
        await _sessionRepository.UpdateAsync(session, cancellationToken);
        _logger.LogInformation("Session {SessionId} revoked", sessionId);
    }

    /// <inheritdoc/>
    public async Task RevokeAllSessionsAsync(
        Guid userId,
        Guid tenantId,
        Guid? exceptSessionId = null,
        CancellationToken cancellationToken = default)
    {
        var result = await _sessionRepository.FindAsync(
            s => s.UserId == userId && s.TenantId == tenantId && s.RevokedAt == null,
            1, int.MaxValue, cancellationToken);

        foreach (var session in result.Items)
        {
            if (exceptSessionId.HasValue && session.Id == exceptSessionId.Value) continue;
            session.RevokedAt = DateTimeOffset.UtcNow;
            await _sessionRepository.UpdateAsync(session, cancellationToken);
        }

        _logger.LogInformation("Revoked all sessions for user {UserId} in tenant {TenantId}", userId, tenantId);
    }
}
