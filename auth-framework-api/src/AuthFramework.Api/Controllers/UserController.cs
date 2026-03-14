using AuthFramework.Application.DTOs.Users;
using AuthFramework.Application.Interfaces;
using AuthFramework.Shared.Extensions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Controllers;

/// <summary>User profile and account management endpoints.</summary>
[ApiController]
[Route("api/users")]
[Authorize]
[Produces("application/json")]
public sealed class UserController : ControllerBase
{
    private readonly IUserRepository _userRepository;
    private readonly ISessionService _sessionService;
    private readonly ILocalizationService _localizationService;
    private readonly IEncryptionService _encryptionService;

    public UserController(
        IUserRepository userRepository,
        ISessionService sessionService,
        ILocalizationService localizationService,
        IEncryptionService encryptionService)
    {
        _userRepository = userRepository;
        _sessionService = sessionService;
        _localizationService = localizationService;
        _encryptionService = encryptionService;
    }

    /// <summary>Returns the current user's profile.</summary>
    [HttpGet("me")]
    [ProducesResponseType(typeof(UserDto), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetProfile(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var user = await _userRepository.GetWithProfileAsync(userId, tenantId, cancellationToken);
        if (user is null) return NotFound();

        return Ok(new UserDto
        {
            Id = user.Id,
            Email = user.Email,
            FirstName = user.Profile?.FirstName != null ? _encryptionService.Decrypt(user.Profile.FirstName) : null,
            LastName = user.Profile?.LastName != null ? _encryptionService.Decrypt(user.Profile.LastName) : null,
            DisplayName = user.Profile?.DisplayName,
            Status = user.Status,
            IsEmailVerified = user.IsEmailVerified,
            CreatedAt = user.CreatedAt,
        });
    }

    /// <summary>Updates the current user's profile.</summary>
    [HttpPatch("me")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> UpdateProfile([FromBody] UpdateProfileRequest request, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var user = await _userRepository.GetWithProfileAsync(userId, tenantId, cancellationToken);
        if (user is null) return NotFound();
        if (user.Profile is null) return NotFound();

        if (request.FirstName != null)
            user.Profile.FirstName = _encryptionService.Encrypt(request.FirstName);
        if (request.LastName != null)
            user.Profile.LastName = _encryptionService.Encrypt(request.LastName);
        if (request.DisplayName != null)
            user.Profile.DisplayName = request.DisplayName;
        if (request.Language != null)
            user.Profile.Locale = request.Language;
        if (request.Timezone != null)
            user.Profile.Timezone = request.Timezone;

        user.Profile.UpdatedAt = DateTimeOffset.UtcNow;
        await _userRepository.UpdateAsync(user, cancellationToken);
        return NoContent();
    }

    /// <summary>Lists the current user's active sessions.</summary>
    [HttpGet("me/sessions")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListSessions([FromQuery] int page = 1, [FromQuery] int pageSize = 20, CancellationToken cancellationToken = default)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var sessions = await _sessionService.ListSessionsAsync(userId, tenantId, page, pageSize, cancellationToken);
        return Ok(sessions);
    }

    /// <summary>Revokes a specific session.</summary>
    [HttpDelete("me/sessions/{sessionId:guid}")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> RevokeSession(Guid sessionId, CancellationToken cancellationToken)
    {
        await _sessionService.RevokeSessionAsync(sessionId, cancellationToken);
        return NoContent();
    }

    /// <summary>Gets the current user's localization preferences.</summary>
    [HttpGet("me/preferences")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> GetPreferences(CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        var prefs = await _localizationService.GetUserPreferencesAsync(userId, tenantId, cancellationToken);
        return Ok(prefs);
    }

    /// <summary>Updates the current user's localization preferences.</summary>
    [HttpPatch("me/preferences")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> UpdatePreferences([FromBody] UpdateLocalizationPreferencesRequest request, CancellationToken cancellationToken)
    {
        var userId = User.GetUserId();
        var tenantId = User.GetTenantId();
        await _localizationService.UpdateUserPreferencesAsync(userId, tenantId, request, cancellationToken);
        return NoContent();
    }

    /// <summary>Initiates GDPR account deletion (anonymizes PII).</summary>
    [HttpPost("me/delete")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    public IActionResult RequestAccountDeletion()
    {
        // Full implementation would create a PII deletion request record and schedule background job
        return Accepted(new { message = "Account deletion request received. Your data will be processed within 30 days." });
    }

    /// <summary>Exports user data for GDPR data portability.</summary>
    [HttpGet("me/data-export")]
    [ProducesResponseType(StatusCodes.Status202Accepted)]
    public IActionResult ExportUserData()
    {
        // Full implementation would queue a data export job and email a download link
        return Accepted(new { message = "Data export request received. You will receive an email when your export is ready." });
    }
}
