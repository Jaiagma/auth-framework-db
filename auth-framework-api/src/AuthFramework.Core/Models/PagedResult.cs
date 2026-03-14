namespace AuthFramework.Core.Models;

/// <summary>Generic paged result wrapper for list queries.</summary>
/// <typeparam name="T">The type of items in the result set.</typeparam>
public sealed class PagedResult<T>
{
    /// <summary>Items on the current page.</summary>
    public IReadOnlyList<T> Items { get; init; } = [];

    /// <summary>Total number of matching records across all pages.</summary>
    public int TotalCount { get; init; }

    /// <summary>Current page number (1-based).</summary>
    public int Page { get; init; }

    /// <summary>Number of items per page.</summary>
    public int PageSize { get; init; }

    /// <summary>Total number of pages.</summary>
    public int TotalPages => PageSize > 0 ? (int)Math.Ceiling((double)TotalCount / PageSize) : 0;

    /// <summary>Whether a previous page exists.</summary>
    public bool HasPreviousPage => Page > 1;

    /// <summary>Whether a next page exists.</summary>
    public bool HasNextPage => Page < TotalPages;

    /// <summary>Creates a paged result.</summary>
    public static PagedResult<T> Create(IReadOnlyList<T> items, int totalCount, int page, int pageSize)
        => new() { Items = items, TotalCount = totalCount, Page = page, PageSize = pageSize };

    /// <summary>Creates an empty paged result.</summary>
    public static PagedResult<T> Empty(int page = 1, int pageSize = 20)
        => new() { Items = [], TotalCount = 0, Page = page, PageSize = pageSize };
}
