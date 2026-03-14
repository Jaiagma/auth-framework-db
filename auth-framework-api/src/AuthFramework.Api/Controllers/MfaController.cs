using AuthFramework.Application.DTOs.Mfa;
using AuthFramework.Application.Interfaces;
using AuthFramework.Shared.Extensions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Controllers;

/// <summary>Multi-factor authentication enrollment and verification endpoints.</summary>
[ApiController]
[Route("api/mfa")]
[Produces("application/json")]
public sealed class MfaController : ControllerBase
{
    private readonly IMfaService _mfaService;

    public MfaController(IMfaService mfaService) => _mfaService = mfaService;

    /// <summary>Enrolls a new MFA device for the authenticated user.</summary>
    [HttpPost("enroll")]
    [Authorize]
    [ProducesResponseType(typeof(EnrollMfaResponse), StatusCodes.Status201Created)]
    public async Task<IActionResult> Enroll([FromBody] EnrollMfaRequest request, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var result = await _mfaService.EnrollDeviceAsync(userId, tenantId, request, cancellationToken);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    /// <summary>Verifies an MFA code for a pending challenge. Does not require an active session.</summary>
    [HttpPost("verify")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Verify([FromBody] VerifyMfaRequest request, [FromQuery] Guid tenantId, CancellationToken cancellationToken)
    {
        var success = await _mfaService.VerifyMfaAsync(tenantId, request, cancellationToken);
        if (!success) return Unauthorized(new { message = "Invalid MFA code." });
        return Ok(new { verified = true });
    }

    /// <summary>Lists all registered MFA devices for the authenticated user.</summary>
    [HttpGet("devices")]
    [Authorize]
    [ProducesResponseType(typeof(IReadOnlyList<MfaDeviceDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetDevices(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var devices = await _mfaService.GetDevicesAsync(userId, tenantId, cancellationToken);
        return Ok(devices);
    }

    /// <summary>Removes an MFA device.</summary>
    [HttpDelete("devices/{deviceId:guid}")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> RemoveDevice(Guid deviceId, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        await _mfaService.RemoveDeviceAsync(userId, tenantId, deviceId, cancellationToken);
        return NoContent();
    }

    /// <summary>Generates a new set of recovery codes, invalidating any previous codes.</summary>
    [HttpPost("recovery-codes/regenerate")]
    [Authorize]
    [ProducesResponseType(typeof(IReadOnlyList<string>), StatusCodes.Status200OK)]
    public async Task<IActionResult> RegenerateRecoveryCodes(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var codes = await _mfaService.GenerateRecoveryCodesAsync(userId, tenantId, cancellationToken);
        return Ok(new { codes });
    }
}
