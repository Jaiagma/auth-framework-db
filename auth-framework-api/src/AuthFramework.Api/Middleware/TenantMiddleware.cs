using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;

namespace AuthFramework.Api.Middleware;

/// <summary>
/// Resolves the tenant from the X-Tenant-ID header or subdomain and validates it is active.
/// Sets the resolved tenant ID in HttpContext.Items["TenantId"].
/// </summary>
public sealed class TenantMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<TenantMiddleware> _logger;

    // Paths that don't require tenant context
    private static readonly HashSet<string> TenantFreeRoutes = new(StringComparer.OrdinalIgnoreCase)
    {
        "/health",
        "/health/ready",
        "/swagger",
        "/swagger/index.html",
        "/swagger/v1/swagger.json",
    };

    public TenantMiddleware(RequestDelegate next, ILogger<TenantMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context, ITenantRepository tenantRepository)
    {
        // Skip tenant resolution for health checks and swagger
        if (TenantFreeRoutes.Any(p => context.Request.Path.StartsWithSegments(p, StringComparison.OrdinalIgnoreCase)))
        {
            await _next(context);
            return;
        }

        Guid? tenantId = null;

        // 1. Try X-Tenant-ID header (GUID)
        if (context.Request.Headers.TryGetValue(AuthConstants.TenantHeader, out var tenantHeaderValue))
        {
            if (Guid.TryParse(tenantHeaderValue, out var parsedId))
                tenantId = parsedId;
        }

        // 2. Try subdomain (e.g., "acme.authframework.example.com")
        if (!tenantId.HasValue)
        {
            var host = context.Request.Host.Host;
            var subdomain = host.Split('.').FirstOrDefault();
            if (!string.IsNullOrEmpty(subdomain) && subdomain != "www" && subdomain != "api")
            {
                var tenant = await tenantRepository.FindBySlugAsync(subdomain, context.RequestAborted);
                if (tenant != null)
                    tenantId = tenant.Id;
            }
        }

        if (tenantId.HasValue)
        {
            context.Items["TenantId"] = tenantId.Value;
            _logger.LogDebug("Tenant {TenantId} resolved for {Path}", tenantId.Value, context.Request.Path);
        }

        await _next(context);
    }
}
