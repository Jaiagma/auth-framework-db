namespace AuthFramework.Application.Interfaces;

/// <summary>Operations for linking external identity provider accounts to local users.</summary>
public interface IFederatedIdentityService
{
    /// <summary>Links an external identity to an existing local user.</summary>
    Task<FederatedIdentityDto> LinkIdentityAsync(Guid userId, Guid tenantId, LinkIdentityRequest request, CancellationToken cancellationToken = default);

    /// <summary>Removes a linked external identity from a user.</summary>
    Task UnlinkIdentityAsync(Guid userId, Guid tenantId, Guid identityId, CancellationToken cancellationToken = default);

    /// <summary>Returns all external identities linked to a user.</summary>
    Task<IReadOnlyList<FederatedIdentityDto>> GetLinkedIdentitiesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default);

    /// <summary>Finds an existing user by federated identity or creates a new user account.</summary>
    Task<FederatedUserResult> FindOrCreateUserFromFederatedIdentityAsync(Guid tenantId, Guid providerId, string externalUserId, string? externalEmail, IDictionary<string, string>? attributes = null, CancellationToken cancellationToken = default);
}

/// <summary>DTO for a federated (external) identity link.</summary>
public record FederatedIdentityDto(Guid Id, Guid ProviderId, string ProviderName, string ExternalUserId, string? ExternalEmail, DateTimeOffset CreatedAt);

/// <summary>Request to link an external identity to a user.</summary>
public record LinkIdentityRequest(Guid ProviderId, string ExternalUserId, string? ExternalEmail);

/// <summary>Result of finding or creating a user from a federated identity.</summary>
public record FederatedUserResult(Guid UserId, bool IsNewUser);
