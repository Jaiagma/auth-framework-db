using AuthFramework.Core.Entities;
using AuthFramework.Core.Models;

namespace AuthFramework.Application.Interfaces;

/// <summary>User session lifecycle management.</summary>
public interface ISessionService
{
    /// <summary>Creates a new session for an authenticated user.</summary>
    Task<UserSession> CreateSessionAsync(Guid userId, Guid tenantId, Guid? applicationId, string? ipAddress, string? userAgent, bool mfaVerified = false, CancellationToken cancellationToken = default);

    /// <summary>Validates that a session is active and not expired or revoked.</summary>
    Task<bool> ValidateSessionAsync(Guid sessionId, CancellationToken cancellationToken = default);

    /// <summary>Retrieves a session by ID.</summary>
    Task<UserSession?> GetSessionAsync(Guid sessionId, CancellationToken cancellationToken = default);

    /// <summary>Lists all active sessions for a user.</summary>
    Task<PagedResult<UserSession>> ListSessionsAsync(Guid userId, Guid tenantId, int page = 1, int pageSize = 20, CancellationToken cancellationToken = default);

    /// <summary>Revokes a specific session.</summary>
    Task RevokeSessionAsync(Guid sessionId, CancellationToken cancellationToken = default);

    /// <summary>Revokes all sessions for a user (e.g., after password change).</summary>
    Task RevokeAllSessionsAsync(Guid userId, Guid tenantId, Guid? exceptSessionId = null, CancellationToken cancellationToken = default);
}
