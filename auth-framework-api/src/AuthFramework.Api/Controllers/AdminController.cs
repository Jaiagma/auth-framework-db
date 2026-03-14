using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Constants;
using AuthFramework.Core.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Controllers;

/// <summary>Administrative endpoints for tenant and user management (requires admin role).</summary>
[ApiController]
[Route("api/admin")]
[Authorize(Policy = PolicyNames.AdminOnly)]
[Produces("application/json")]
public sealed class AdminController : ControllerBase
{
    private readonly IUserRepository _userRepository;
    private readonly ITenantRepository _tenantRepository;
    private readonly IAuditService _auditService;

    public AdminController(
        IUserRepository userRepository,
        ITenantRepository tenantRepository,
        IAuditService auditService)
    {
        _userRepository = userRepository;
        _tenantRepository = tenantRepository;
        _auditService = auditService;
    }

    /// <summary>Lists all users in the current tenant.</summary>
    [HttpGet("users")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListUsers(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var tenantId = GetTenantId();
        var users = await _userRepository.FindAsync(u => u.TenantId == tenantId, page, pageSize, cancellationToken);
        return Ok(users);
    }

    /// <summary>Gets a specific user by ID.</summary>
    [HttpGet("users/{userId:guid}")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetUser(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = GetTenantId();
        var user = await _userRepository.GetWithProfileAsync(userId, tenantId, cancellationToken);
        if (user is null) return NotFound();
        return Ok(user);
    }

    /// <summary>Soft-deletes a user.</summary>
    [HttpDelete("users/{userId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> DeleteUser(Guid userId, CancellationToken cancellationToken)
    {
        var tenantId = GetTenantId();
        var user = await _userRepository.GetByIdAsync(userId, cancellationToken);
        if (user is null || user.TenantId != tenantId) return NotFound();

        user.DeletedAt = DateTimeOffset.UtcNow;
        user.UpdatedAt = DateTimeOffset.UtcNow;
        await _userRepository.UpdateAsync(user, cancellationToken);
        return NoContent();
    }

    /// <summary>Retrieves audit logs for the current tenant.</summary>
    [HttpGet("audit-logs")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAuditLogs(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        var tenantId = GetTenantId();
        var logs = await _auditService.GetAuditLogsAsync(tenantId, page, pageSize, cancellationToken);
        return Ok(logs);
    }

    /// <summary>Retrieves security events for the current tenant.</summary>
    [HttpGet("security-events")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetSecurityEvents(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50,
        CancellationToken cancellationToken = default)
    {
        var tenantId = GetTenantId();
        var events = await _auditService.GetSecurityEventsAsync(tenantId, page, pageSize, cancellationToken);
        return Ok(events);
    }

    /// <summary>Lists all tenants (super admin only).</summary>
    [HttpGet("tenants")]
    [Authorize(Policy = PolicyNames.SuperAdmin)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListTenants(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        CancellationToken cancellationToken = default)
    {
        var tenants = await _tenantRepository.FindAsync(_ => true, page, pageSize, cancellationToken);
        return Ok(tenants);
    }

    private Guid GetTenantId()
        => HttpContext.Items.TryGetValue("TenantId", out var tid) && tid is Guid id
            ? id
            : User.FindFirst(AuthFramework.Core.Constants.AuthConstants.TenantIdClaim) is { } claim
                && Guid.TryParse(claim.Value, out var claimId) ? claimId : Guid.Empty;
}
