using System.Linq.Expressions;
using AuthFramework.Core.Models;

namespace AuthFramework.Application.Interfaces;

/// <summary>Generic repository interface providing standard CRUD operations.</summary>
/// <typeparam name="T">The entity type.</typeparam>
public interface IRepository<T> where T : class
{
    /// <summary>Retrieves an entity by its primary key.</summary>
    Task<T?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Retrieves all entities (use with caution on large tables).</summary>
    Task<IReadOnlyList<T>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>Retrieves a paged list of entities matching the predicate.</summary>
    Task<PagedResult<T>> FindAsync(Expression<Func<T, bool>> predicate, int page = 1, int pageSize = 20, CancellationToken cancellationToken = default);

    /// <summary>Adds a new entity to the store.</summary>
    Task<T> AddAsync(T entity, CancellationToken cancellationToken = default);

    /// <summary>Updates an existing entity.</summary>
    Task UpdateAsync(T entity, CancellationToken cancellationToken = default);

    /// <summary>Deletes an entity by ID (hard delete unless soft-delete is configured).</summary>
    Task DeleteAsync(Guid id, CancellationToken cancellationToken = default);

    /// <summary>Checks whether any entity matching the predicate exists.</summary>
    Task<bool> ExistsAsync(Expression<Func<T, bool>> predicate, CancellationToken cancellationToken = default);
}
