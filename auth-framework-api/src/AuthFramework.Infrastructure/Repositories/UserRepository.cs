using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Entities;
using AuthFramework.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace AuthFramework.Infrastructure.Repositories;

/// <summary>User repository with tenant-scoped lookups.</summary>
public sealed class UserRepository : Repository<User>, IUserRepository
{
    public UserRepository(AuthDbContext context) : base(context) { }

    /// <inheritdoc/>
    public async Task<User?> FindByEmailAndTenantAsync(string email, Guid tenantId, CancellationToken cancellationToken = default)
        => await Context.Users
            .Where(u => u.Email == email.ToLowerInvariant() && u.TenantId == tenantId)
            .FirstOrDefaultAsync(cancellationToken);

    /// <inheritdoc/>
    public async Task<User?> FindByEmailHashAsync(string emailHash, Guid tenantId, CancellationToken cancellationToken = default)
        => await Context.Users
            .Where(u => u.EmailHash == emailHash && u.TenantId == tenantId)
            .FirstOrDefaultAsync(cancellationToken);

    /// <inheritdoc/>
    public async Task<User?> GetWithProfileAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default)
        => await Context.Users
            .Include(u => u.Profile)
            .Where(u => u.Id == userId && u.TenantId == tenantId)
            .FirstOrDefaultAsync(cancellationToken);

    /// <inheritdoc/>
    public async Task IncrementFailedLoginAttemptsAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var user = await GetByIdAsync(userId, cancellationToken);
        if (user is null) return;

        user.FailedLoginAttempts++;
        if (user.FailedLoginAttempts >= AuthConstants.MaxFailedLoginAttempts)
            user.LockedUntil = DateTimeOffset.UtcNow.AddMinutes(AuthConstants.AccountLockDurationMinutes);

        user.UpdatedAt = DateTimeOffset.UtcNow;
        await UpdateAsync(user, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task ResetFailedLoginAttemptsAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        var user = await GetByIdAsync(userId, cancellationToken);
        if (user is null) return;

        user.FailedLoginAttempts = 0;
        user.LockedUntil = null;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await UpdateAsync(user, cancellationToken);
    }
}
