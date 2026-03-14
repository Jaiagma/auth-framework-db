using AuthFramework.Core.Entities;

namespace AuthFramework.Application.Interfaces;

/// <summary>User-specific repository operations beyond generic CRUD.</summary>
public interface IUserRepository : IRepository<User>
{
    /// <summary>Finds a user by email within a specific tenant.</summary>
    Task<User?> FindByEmailAndTenantAsync(string email, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Finds a user by email hash for indexed lookups.</summary>
    Task<User?> FindByEmailHashAsync(string emailHash, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Gets a user with all related profile and credential data.</summary>
    Task<User?> GetWithProfileAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Increments the failed login attempt counter and optionally locks the account.</summary>
    Task IncrementFailedLoginAttemptsAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Resets the failed login attempt counter after a successful login.</summary>
    Task ResetFailedLoginAttemptsAsync(Guid userId, CancellationToken cancellationToken = default);
}
