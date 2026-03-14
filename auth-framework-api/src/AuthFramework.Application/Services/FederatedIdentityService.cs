using AuthFramework.Application.Interfaces;
using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Shared.Utilities;
using Microsoft.Extensions.Logging;

namespace AuthFramework.Application.Services;

/// <summary>Manages linking and lookup of external federated identities.</summary>
public sealed class FederatedIdentityService : IFederatedIdentityService
{
    private readonly IRepository<FederatedIdentity> _federatedRepository;
    private readonly IRepository<IdentityProvider> _providerRepository;
    private readonly IUserRepository _userRepository;
    private readonly ILogger<FederatedIdentityService> _logger;

    public FederatedIdentityService(
        IRepository<FederatedIdentity> federatedRepository,
        IRepository<IdentityProvider> providerRepository,
        IUserRepository userRepository,
        ILogger<FederatedIdentityService> logger)
    {
        _federatedRepository = federatedRepository;
        _providerRepository = providerRepository;
        _userRepository = userRepository;
        _logger = logger;
    }

    /// <inheritdoc/>
    public async Task<FederatedIdentityDto> LinkIdentityAsync(Guid userId, Guid tenantId, LinkIdentityRequest request, CancellationToken cancellationToken = default)
    {
        var provider = await _providerRepository.GetByIdAsync(request.ProviderId, cancellationToken)
            ?? throw new InvalidOperationException("Identity provider not found.");

        var existing = await _federatedRepository.FindAsync(
            f => f.UserId == userId && f.ProviderId == request.ProviderId && f.ExternalUserId == request.ExternalUserId,
            cancellationToken: cancellationToken);

        if (existing.Items.Count > 0)
            throw new InvalidOperationException("Identity already linked.");

        var identity = new FederatedIdentity
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = userId,
            TenantId = tenantId,
            ProviderId = request.ProviderId,
            ExternalUserId = request.ExternalUserId,
            ExternalEmail = request.ExternalEmail,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        await _federatedRepository.AddAsync(identity, cancellationToken);
        return new FederatedIdentityDto(identity.Id, provider.Id, provider.Name, identity.ExternalUserId, identity.ExternalEmail, identity.CreatedAt);
    }

    /// <inheritdoc/>
    public async Task UnlinkIdentityAsync(Guid userId, Guid tenantId, Guid identityId, CancellationToken cancellationToken = default)
    {
        var identity = await _federatedRepository.GetByIdAsync(identityId, cancellationToken)
            ?? throw new InvalidOperationException("Federated identity not found.");

        if (identity.UserId != userId)
            throw new UnauthorizedAccessException("Cannot unlink identity belonging to another user.");

        await _federatedRepository.DeleteAsync(identityId, cancellationToken);
    }

    /// <inheritdoc/>
    public async Task<IReadOnlyList<FederatedIdentityDto>> GetLinkedIdentitiesAsync(Guid userId, Guid tenantId, CancellationToken cancellationToken = default)
    {
        var results = await _federatedRepository.FindAsync(
            f => f.UserId == userId && f.TenantId == tenantId,
            1, 100, cancellationToken);

        var dtos = new List<FederatedIdentityDto>();
        foreach (var identity in results.Items)
        {
            var provider = await _providerRepository.GetByIdAsync(identity.ProviderId, cancellationToken);
            dtos.Add(new FederatedIdentityDto(identity.Id, identity.ProviderId, provider?.Name ?? "Unknown",
                identity.ExternalUserId, identity.ExternalEmail, identity.CreatedAt));
        }
        return dtos;
    }

    /// <inheritdoc/>
    public async Task<FederatedUserResult> FindOrCreateUserFromFederatedIdentityAsync(
        Guid tenantId, Guid providerId, string externalUserId, string? externalEmail,
        IDictionary<string, string>? attributes = null, CancellationToken cancellationToken = default)
    {
        var existing = await _federatedRepository.FindAsync(
            f => f.TenantId == tenantId && f.ProviderId == providerId && f.ExternalUserId == externalUserId,
            cancellationToken: cancellationToken);

        if (existing.Items.Count > 0)
            return new FederatedUserResult(existing.Items[0].UserId, false);

        // Create a new stub user - full impl would populate from IDP claims
        var now = DateTimeOffset.UtcNow;
        var user = new User
        {
            Id = UuidV7Generator.NewGuid(),
            TenantId = tenantId,
            Email = externalEmail ?? $"{externalUserId}@federated.local",
            EmailHash = externalUserId,
            Status = UserStatus.Active,
            IsEmailVerified = externalEmail != null,
            CreatedAt = now,
            UpdatedAt = now,
        };

        await _userRepository.AddAsync(user, cancellationToken);

        var identity = new FederatedIdentity
        {
            Id = UuidV7Generator.NewGuid(),
            UserId = user.Id,
            TenantId = tenantId,
            ProviderId = providerId,
            ExternalUserId = externalUserId,
            ExternalEmail = externalEmail,
            CreatedAt = now,
            UpdatedAt = now,
        };

        await _federatedRepository.AddAsync(identity, cancellationToken);
        _logger.LogInformation("Created federated user {UserId} from provider {ProviderId}", user.Id, providerId);
        return new FederatedUserResult(user.Id, true);
    }
}
