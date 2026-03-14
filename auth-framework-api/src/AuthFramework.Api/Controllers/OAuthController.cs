using AuthFramework.Application.DTOs.OAuth;
using AuthFramework.Application.Interfaces;
using AuthFramework.Shared.Extensions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Controllers;

/// <summary>OAuth 2.0 authorization server endpoints.</summary>
[ApiController]
[Route("api/oauth")]
[Produces("application/json")]
public sealed class OAuthController : ControllerBase
{
    private readonly IOAuthService _oauthService;

    public OAuthController(IOAuthService oauthService) => _oauthService = oauthService;

    /// <summary>Registers a new OAuth application.</summary>
    [HttpPost("applications")]
    [Authorize]
    [ProducesResponseType(typeof(OAuthApplicationDto), StatusCodes.Status201Created)]
    public async Task<IActionResult> CreateApplication([FromBody] CreateApplicationRequest request, CancellationToken cancellationToken)
    {
        var tenantId = User.GetTenantId();
        var app = await _oauthService.CreateApplicationAsync(tenantId, request, cancellationToken);
        return StatusCode(StatusCodes.Status201Created, app);
    }

    /// <summary>Gets an OAuth application by ID.</summary>
    [HttpGet("applications/{applicationId:guid}")]
    [Authorize]
    [ProducesResponseType(typeof(OAuthApplicationDto), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetApplication(Guid applicationId, CancellationToken cancellationToken)
    {
        var tenantId = User.GetTenantId();
        var app = await _oauthService.GetApplicationAsync(applicationId, tenantId, cancellationToken);
        if (app is null) return NotFound();
        return Ok(app);
    }

    /// <summary>OAuth 2.0 authorization endpoint. Redirects to redirect_uri with code.</summary>
    [HttpGet("authorize")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status302Found)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Authorize([FromQuery] AuthorizeRequest request, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var code = await _oauthService.AuthorizeAsync(userId, tenantId, request, cancellationToken);
        var redirectUrl = $"{request.RedirectUri}?code={Uri.EscapeDataString(code)}&state={Uri.EscapeDataString(request.State ?? string.Empty)}";
        return Redirect(redirectUrl);
    }

    /// <summary>OAuth 2.0 token endpoint. Exchanges codes or refresh tokens for access tokens.</summary>
    [HttpPost("token")]
    [ProducesResponseType(typeof(TokenResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Token([FromForm] TokenRequest request, CancellationToken cancellationToken)
    {
        var response = await _oauthService.ExchangeCodeAsync(request, cancellationToken);
        return Ok(response);
    }

    /// <summary>Revokes an access or refresh token.</summary>
    [HttpPost("revoke")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> Revoke([FromForm] string token, [FromForm] string? token_type_hint, CancellationToken cancellationToken)
    {
        var tenantId = HttpContext.Items.TryGetValue("TenantId", out var tid) && tid is Guid id ? id : Guid.Empty;
        if (tenantId == Guid.Empty) return BadRequest("Tenant context required.");
        await _oauthService.RevokeTokenAsync(token, token_type_hint, tenantId, cancellationToken);
        return Ok();
    }

    /// <summary>Introspects a token (RFC 7662).</summary>
    [HttpPost("introspect")]
    [ProducesResponseType(typeof(TokenIntrospectionResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> Introspect([FromForm] string token, CancellationToken cancellationToken)
    {
        var tenantId = HttpContext.Items.TryGetValue("TenantId", out var tid) && tid is Guid id ? id : Guid.Empty;
        if (tenantId == Guid.Empty) return BadRequest("Tenant context required.");
        var result = await _oauthService.IntrospectTokenAsync(token, tenantId, cancellationToken);
        return Ok(result);
    }
}
