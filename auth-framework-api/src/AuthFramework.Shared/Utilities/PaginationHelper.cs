namespace AuthFramework.Shared.Utilities;

/// <summary>Helpers for constructing pagination parameters.</summary>
public static class PaginationHelper
{
    /// <summary>Default page size.</summary>
    public const int DefaultPageSize = 20;

    /// <summary>Maximum page size to prevent oversized queries.</summary>
    public const int MaxPageSize = 100;

    /// <summary>Normalizes page and pageSize values to valid ranges.</summary>
    public static (int page, int pageSize) Normalize(int page, int pageSize)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 1, MaxPageSize);
        return (page, pageSize);
    }

    /// <summary>Calculates the number of items to skip for a given page.</summary>
    public static int Skip(int page, int pageSize) => (Math.Max(1, page) - 1) * pageSize;
}
