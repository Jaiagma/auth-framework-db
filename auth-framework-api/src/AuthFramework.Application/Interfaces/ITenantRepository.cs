using AuthFramework.Core.Entities;

namespace AuthFramework.Application.Interfaces;

/// <summary>Tenant-specific repository operations.</summary>
public interface ITenantRepository : IRepository<Tenant>
{
    /// <summary>Finds a tenant by its URL slug.</summary>
    Task<Tenant?> FindBySlugAsync(string slug, CancellationToken cancellationToken = default);

    /// <summary>Finds a tenant by its unique name.</summary>
    Task<Tenant?> FindByNameAsync(string name, CancellationToken cancellationToken = default);

    /// <summary>Checks if a slug is available (not already taken).</summary>
    Task<bool> IsSlugAvailableAsync(string slug, Guid? excludeTenantId = null, CancellationToken cancellationToken = default);
}
