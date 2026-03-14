using System.Text.Json;
using AuthFramework.Core.Enums;

namespace AuthFramework.Core.Entities;

/// <summary>Immutable audit log entry for compliance and forensic analysis.</summary>
public class AuditLog
{
    /// <summary>Unique identifier (UUID v7, sortable by time).</summary>
    public Guid Id { get; set; }

    /// <summary>Tenant context for this event.</summary>
    public Guid TenantId { get; set; }

    /// <summary>User who performed the action (null for system events).</summary>
    public Guid? UserId { get; set; }

    /// <summary>High-level category of the event.</summary>
    public AuditEventType EventType { get; set; }

    /// <summary>Type of resource affected (e.g., "User", "Application").</summary>
    public string? ResourceType { get; set; }

    /// <summary>ID of the resource affected.</summary>
    public string? ResourceId { get; set; }

    /// <summary>Specific action performed (e.g., "login", "password_change").</summary>
    public string Action { get; set; } = string.Empty;

    /// <summary>Outcome of the action (e.g., "success", "failure").</summary>
    public string? Status { get; set; }

    /// <summary>Client IP address.</summary>
    public string? IpAddress { get; set; }

    /// <summary>Client User-Agent string.</summary>
    public string? UserAgent { get; set; }

    /// <summary>Additional event details as JSONB.</summary>
    public JsonDocument? Details { get; set; }

    /// <summary>When the event occurred.</summary>
    public DateTimeOffset CreatedAt { get; set; }

    // Navigation
    /// <summary>User who performed the action.</summary>
    public User? User { get; set; }
}
