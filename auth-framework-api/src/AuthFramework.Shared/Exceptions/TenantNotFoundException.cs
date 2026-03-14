namespace AuthFramework.Shared.Exceptions;

/// <summary>Thrown when a referenced tenant cannot be found.</summary>
public class TenantNotFoundException : AuthFrameworkException
{
    /// <summary>The tenant ID that was not found.</summary>
    public Guid TenantId { get; }

    /// <inheritdoc/>
    public TenantNotFoundException(Guid tenantId)
        : base($"Tenant '{tenantId}' was not found.", "TENANT_NOT_FOUND")
    {
        TenantId = tenantId;
    }

    /// <inheritdoc/>
    public TenantNotFoundException(string slug)
        : base($"Tenant with slug '{slug}' was not found.", "TENANT_NOT_FOUND")
    {
        TenantId = Guid.Empty;
    }
}
