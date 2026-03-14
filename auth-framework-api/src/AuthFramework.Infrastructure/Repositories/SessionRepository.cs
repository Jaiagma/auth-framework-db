using AuthFramework.Core.Entities;
using AuthFramework.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace AuthFramework.Infrastructure.Repositories;

/// <summary>Session repository with validity-aware queries.</summary>
public sealed class SessionRepository : Repository<UserSession>
{
    public SessionRepository(AuthDbContext context) : base(context) { }

    /// <summary>Finds a session that is still valid (not revoked and not expired).</summary>
    public async Task<UserSession?> FindValidSessionAsync(Guid sessionId, CancellationToken cancellationToken = default)
        => await Context.UserSessions
            .Where(s => s.Id == sessionId && s.RevokedAt == null && s.ExpiresAt > DateTimeOffset.UtcNow)
            .FirstOrDefaultAsync(cancellationToken);

    /// <summary>Updates the last activity timestamp for a session.</summary>
    public async Task TouchAsync(Guid sessionId, CancellationToken cancellationToken = default)
    {
        await Context.UserSessions
            .Where(s => s.Id == sessionId)
            .ExecuteUpdateAsync(
                setters => setters.SetProperty(s => s.LastActivityAt, DateTimeOffset.UtcNow),
                cancellationToken);
    }
}
