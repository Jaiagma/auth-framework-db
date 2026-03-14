using AuthFramework.Core.Enums;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Models;
using System.Text.Json;

namespace AuthFramework.Application.Interfaces;

/// <summary>Audit logging and security event tracking.</summary>
public interface IAuditService
{
    /// <summary>Records an audit event to the persistent audit log.</summary>
    Task LogEventAsync(
        Guid tenantId,
        AuditEventType eventType,
        string action,
        string? status = null,
        Guid? userId = null,
        string? resourceType = null,
        string? resourceId = null,
        string? ipAddress = null,
        string? userAgent = null,
        JsonDocument? details = null,
        CancellationToken cancellationToken = default);

    /// <summary>Retrieves a paged list of audit logs for a tenant.</summary>
    Task<PagedResult<AuditLog>> GetAuditLogsAsync(Guid tenantId, int page = 1, int pageSize = 50, CancellationToken cancellationToken = default);

    /// <summary>Retrieves security-related audit events for a tenant.</summary>
    Task<PagedResult<AuditLog>> GetSecurityEventsAsync(Guid tenantId, int page = 1, int pageSize = 50, CancellationToken cancellationToken = default);
}
