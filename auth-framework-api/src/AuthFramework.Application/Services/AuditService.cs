using System.Text.Json;
using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Core.Models;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Logging;

namespace AuthFramework.Application.Services;

/// <summary>Persists audit events to the audit_logs table.</summary>
public sealed class AuditService : IAuditService
{
    private readonly IRepository<AuditLog> _auditLogRepository;
    private readonly ILogger<AuditService> _logger;

    public AuditService(IRepository<AuditLog> auditLogRepository, ILogger<AuditService> logger)
    {
        _auditLogRepository = auditLogRepository;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task LogEventAsync(
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
        CancellationToken cancellationToken = default)
    {
        try
        {
            var entry = new AuditLog
            {
                Id = UuidV7Generator.NewGuid(),
                TenantId = tenantId,
                UserId = userId,
                EventType = eventType,
                Action = action,
                Status = status,
                ResourceType = resourceType,
                ResourceId = resourceId,
                IpAddress = ipAddress,
                UserAgent = userAgent,
                Details = details,
                CreatedAt = DateTimeOffset.UtcNow,
            };

            await _auditLogRepository.AddAsync(entry, cancellationToken);
        }
        catch (Exception ex)
        {
            // Audit logging must never throw - log the failure and continue
            _logger.LogError(ex, "Failed to persist audit log entry for action {Action} in tenant {TenantId}", action, tenantId);
        }
    }

    /// <inheritdoc/>
    public async Task<PagedResult<AuditLog>> GetAuditLogsAsync(Guid tenantId, int page = 1, int pageSize = 50, CancellationToken cancellationToken = default)
        => await _auditLogRepository.FindAsync(al => al.TenantId == tenantId, page, pageSize, cancellationToken);

    /// <inheritdoc/>
    public async Task<PagedResult<AuditLog>> GetSecurityEventsAsync(Guid tenantId, int page = 1, int pageSize = 50, CancellationToken cancellationToken = default)
        => await _auditLogRepository.FindAsync(
            al => al.TenantId == tenantId && al.EventType == AuditEventType.Security,
            page, pageSize, cancellationToken);
}
