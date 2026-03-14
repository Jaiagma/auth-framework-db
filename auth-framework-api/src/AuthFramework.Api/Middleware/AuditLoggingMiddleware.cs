using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Enums;
using AuthFramework.Shared.Extensions;

namespace AuthFramework.Api.Middleware;

/// <summary>Logs API requests to the audit trail for security-sensitive endpoints.</summary>
public sealed class AuditLoggingMiddleware
{
    private readonly RequestDelegate _next;

    // Only audit these path prefixes
    private static readonly string[] AuditedPrefixes =
        ["/api/auth", "/api/mfa", "/api/oauth", "/api/admin"];

    public AuditLoggingMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context, IAuditService auditService)
    {
        var shouldAudit = AuditedPrefixes.Any(p =>
            context.Request.Path.StartsWithSegments(p, StringComparison.OrdinalIgnoreCase));

        await _next(context);

        if (!shouldAudit) return;

        var userId = context.User.GetUserId();
        var tenantId = context.User.GetTenantId();

        if (tenantId == Guid.Empty && context.Items.TryGetValue("TenantId", out var ti) && ti is Guid tid)
            tenantId = tid;

        if (tenantId == Guid.Empty) return;

        var action = $"{context.Request.Method} {context.Request.Path}";
        var status = context.Response.StatusCode < 400 ? "success" : "failure";
        var ipAddress = context.Connection.RemoteIpAddress?.ToString();
        var userAgent = context.Request.Headers.UserAgent.ToString();

        await auditService.LogEventAsync(
            tenantId,
            AuditEventType.Authentication,
            action,
            status,
            userId == Guid.Empty ? null : userId,
            ipAddress: ipAddress,
            userAgent: userAgent);
    }
}
