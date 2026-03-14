using System.Linq.Expressions;
using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Models;
using AuthFramework.Infrastructure.Data;
using AuthFramework.Shared.Utilities;
using Microsoft.EntityFrameworkCore;

namespace AuthFramework.Infrastructure.Repositories;

/// <summary>Generic EF Core repository providing standard CRUD with paging.</summary>
public class Repository<T> : IRepository<T> where T : class
{
    protected readonly AuthDbContext Context;
    protected readonly DbSet<T> DbSet;

    public Repository(AuthDbContext context)
    {
        Context = context;
        DbSet = context.Set<T>();
    }

    /// <inheritdoc/>
    public virtual async Task<T?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
        => await DbSet.FindAsync([id], cancellationToken);

    /// <inheritdoc/>
    public virtual async Task<IReadOnlyList<T>> GetAllAsync(CancellationToken cancellationToken = default)
        => await DbSet.ToListAsync(cancellationToken);

    /// <inheritdoc/>
    public virtual async Task<PagedResult<T>> FindAsync(
        Expression<Func<T, bool>> predicate,
        int page = 1,
        int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var (normalizedPage, normalizedPageSize) = PaginationHelper.Normalize(page, pageSize);

        var query = DbSet.Where(predicate);
        var totalCount = await query.CountAsync(cancellationToken);
        var items = await query
            .Skip(PaginationHelper.Skip(normalizedPage, normalizedPageSize))
            .Take(normalizedPageSize)
            .ToListAsync(cancellationToken);

        return PagedResult<T>.Create(items, totalCount, normalizedPage, normalizedPageSize);
    }

    /// <inheritdoc/>
    public virtual async Task<T> AddAsync(T entity, CancellationToken cancellationToken = default)
    {
        await DbSet.AddAsync(entity, cancellationToken);
        await Context.SaveChangesAsync(cancellationToken);
        return entity;
    }

    /// <inheritdoc/>
    public virtual async Task UpdateAsync(T entity, CancellationToken cancellationToken = default)
    {
        DbSet.Update(entity);
        await Context.SaveChangesAsync(cancellationToken);
    }

    /// <inheritdoc/>
    public virtual async Task DeleteAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var entity = await GetByIdAsync(id, cancellationToken);
        if (entity is not null)
        {
            DbSet.Remove(entity);
            await Context.SaveChangesAsync(cancellationToken);
        }
    }

    /// <inheritdoc/>
    public virtual async Task<bool> ExistsAsync(
        Expression<Func<T, bool>> predicate,
        CancellationToken cancellationToken = default)
        => await DbSet.AnyAsync(predicate, cancellationToken);
}
