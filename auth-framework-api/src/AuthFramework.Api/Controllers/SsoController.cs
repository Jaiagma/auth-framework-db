using AuthFramework.Application.Interfaces;
using AuthFramework.Shared.Extensions;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Controllers;

/// <summary>Single Sign-On (SSO) endpoints for external identity provider integration.</summary>
[ApiController]
[Route("api/sso")]
[Produces("application/json")]
public sealed class SsoController : ControllerBase
{
    private readonly ISsoService _ssoService;

    public SsoController(ISsoService ssoService) => _ssoService = ssoService;

    /// <summary>Lists available SSO providers for a tenant.</summary>
    [HttpGet("providers")]
    [ProducesResponseType(typeof(IReadOnlyList<SsoProviderDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetProviders(CancellationToken cancellationToken)
    {
        var tenantId = GetTenantId();
        var providers = await _ssoService.GetProvidersAsync(tenantId, cancellationToken);
        return Ok(providers);
    }

    /// <summary>Initiates an SSO login with the specified provider.</summary>
    [HttpGet("login/{provider}")]
    [ProducesResponseType(StatusCodes.Status302Found)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> InitiateSso(string provider, [FromQuery] string? returnUrl, CancellationToken cancellationToken)
    {
        var tenantId = GetTenantId();
        var redirectUrl = await _ssoService.InitiateSsoAsync(tenantId, provider, returnUrl, cancellationToken);
        return Redirect(redirectUrl);
    }

    /// <summary>Processes the callback from an SSO provider.</summary>
    [HttpPost("callback")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ProcessCallback([FromQuery] string provider, [FromQuery] string code, [FromQuery] string? state, CancellationToken cancellationToken)
    {
        var tenantId = GetTenantId();
        var result = await _ssoService.ProcessSsoCallbackAsync(tenantId, provider, code, state, cancellationToken);
        if (!result.Success) return BadRequest(new { error = result.ErrorMessage });
        return Ok(new { accessToken = result.AccessToken, refreshToken = result.RefreshToken });
    }

    /// <summary>Returns the current SSO session for the authenticated user.</summary>
    [HttpGet("session")]
    [Microsoft.AspNetCore.Authorization.Authorize]
    [ProducesResponseType(typeof(SsoSessionDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSsoSession(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var session = await _ssoService.GetSsoSessionAsync(userId, tenantId, cancellationToken);
        if (session is null) return NotFound();
        return Ok(session);
    }

    private Guid GetTenantId()
        => HttpContext.Items.TryGetValue("TenantId", out var tid) && tid is Guid id ? id : Guid.Empty;
}
