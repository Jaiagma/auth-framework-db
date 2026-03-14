using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Entities;
using AuthFramework.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;

namespace AuthFramework.Infrastructure.Repositories;

/// <summary>Tenant repository with slug-based lookups.</summary>
public sealed class TenantRepository : Repository<Tenant>, ITenantRepository
{
    public TenantRepository(AuthDbContext context) : base(context) { }

    /// <inheritdoc/>
    public async Task<Tenant?> FindBySlugAsync(string slug, CancellationToken cancellationToken = default)
        => await Context.Tenants
            .Where(t => t.Slug == slug.ToLowerInvariant())
            .FirstOrDefaultAsync(cancellationToken);

    /// <inheritdoc/>
    public async Task<Tenant?> FindByNameAsync(string name, CancellationToken cancellationToken = default)
        => await Context.Tenants
            .Where(t => t.Name == name)
            .FirstOrDefaultAsync(cancellationToken);

    /// <inheritdoc/>
    public async Task<bool> IsSlugAvailableAsync(string slug, Guid? excludeTenantId = null, CancellationToken cancellationToken = default)
    {
        var query = Context.Tenants.Where(t => t.Slug == slug.ToLowerInvariant());
        if (excludeTenantId.HasValue)
            query = query.Where(t => t.Id != excludeTenantId.Value);
        return !await query.AnyAsync(cancellationToken);
    }
}
