using AuthFramework.Core.Enums;

namespace AuthFramework.Application.DTOs.OAuth;

/// <summary>Request to register a new OAuth application.</summary>
public sealed class CreateApplicationRequest
{
    /// <summary>Human-readable application name.</summary>
    public string Name { get; init; } = string.Empty;

    /// <summary>Type of OAuth application.</summary>
    public ApplicationType ApplicationType { get; init; }

    /// <summary>Allowed redirect URIs.</summary>
    public string[] RedirectUris { get; init; } = [];

    /// <summary>Scopes this application is allowed to request.</summary>
    public string[] AllowedScopes { get; init; } = [];
}

/// <summary>DTO representing an OAuth application.</summary>
public sealed class OAuthApplicationDto
{
    /// <summary>Application ID.</summary>
    public Guid Id { get; init; }

    /// <summary>Application name.</summary>
    public string Name { get; init; } = string.Empty;

    /// <summary>OAuth client_id.</summary>
    public string ClientId { get; init; } = string.Empty;

    /// <summary>Client secret (only returned on creation).</summary>
    public string? ClientSecret { get; init; }

    /// <summary>Application type.</summary>
    public ApplicationType ApplicationType { get; init; }

    /// <summary>Allowed redirect URIs.</summary>
    public string[] RedirectUris { get; init; } = [];

    /// <summary>Whether the application is active.</summary>
    public bool IsActive { get; init; }
}
