namespace AuthFramework.Application.Interfaces;

/// <summary>Localization and user preference management.</summary>
public interface ILocalizationService
{
    /// <summary>Returns all supported languages.</summary>
    Task<IReadOnlyList<LanguageDto>> GetSupportedLanguagesAsync(CancellationToken cancellationToken = default);

    /// <summary>Returns all supported timezones.</summary>
    Task<IReadOnlyList<TimezoneDto>> GetTimezonesAsync(CancellationToken cancellationToken = default);

    /// <summary>Retrieves a user's localization preferences.</summary>
    Task<UserLocalizationPreferencesDto?> GetUserPreferencesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Updates a user's localization preferences.</summary>
    Task UpdateUserPreferencesAsync(Guid userId, Guid tenantId, UpdateLocalizationPreferencesRequest request, CancellationToken cancellationToken = default);
}

/// <summary>Supported language information.</summary>
public record LanguageDto(string Code, string Name, string NativeName, bool IsRtl);

/// <summary>Timezone information.</summary>
public record TimezoneDto(string Id, string DisplayName, string UtcOffset);

/// <summary>User localization preferences.</summary>
public record UserLocalizationPreferencesDto(string? Language, string? Timezone, string? DateFormat, string? TimeFormat);

/// <summary>Request to update localization preferences.</summary>
public record UpdateLocalizationPreferencesRequest(string? Language, string? Timezone, string? DateFormat, string? TimeFormat);
