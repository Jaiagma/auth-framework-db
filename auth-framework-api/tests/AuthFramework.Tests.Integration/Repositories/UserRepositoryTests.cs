using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using AuthFramework.Infrastructure.Repositories;
using AuthFramework.Shared.Utilities;
using FluentAssertions;
using Xunit;

namespace AuthFramework.Tests.Integration.Repositories;

/// <summary>Integration tests for the UserRepository using a real PostgreSQL container.</summary>
[Collection("Database")]
public sealed class UserRepositoryTests : IClassFixture<DatabaseFixture>
{
    private readonly DatabaseFixture _fixture;

    public UserRepositoryTests(DatabaseFixture fixture) => _fixture = fixture;

    private UserRepository CreateRepository() => new(_fixture.DbContext);

    private static Tenant CreateTenant() => new()
    {
        Id = UuidV7Generator.NewGuid(),
        Name = $"Test Tenant {Guid.NewGuid():N}",
        Slug = $"test-{Guid.NewGuid():N}",
        Status = TenantStatus.Active,
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow,
    };

    private static User CreateUser(Guid tenantId, string email) => new()
    {
        Id = UuidV7Generator.NewGuid(),
        TenantId = tenantId,
        Email = email,
        EmailHash = email.GetHashCode().ToString(),
        Status = UserStatus.Active,
        IsEmailVerified = true,
        CreatedAt = DateTimeOffset.UtcNow,
        UpdatedAt = DateTimeOffset.UtcNow,
    };

    [Fact]
    public async Task AddAsync_And_GetByIdAsync_RoundTrip()
    {
        // Arrange
        var tenant = CreateTenant();
        await _fixture.DbContext.Tenants.AddAsync(tenant);
        await _fixture.DbContext.SaveChangesAsync();

        var repo = CreateRepository();
        var user = CreateUser(tenant.Id, "integration@example.com");

        // Act
        var added = await repo.AddAsync(user);
        var retrieved = await repo.GetByIdAsync(added.Id);

        // Assert
        retrieved.Should().NotBeNull();
        retrieved!.Email.Should().Be("integration@example.com");
        retrieved.TenantId.Should().Be(tenant.Id);
    }

    [Fact]
    public async Task FindByEmailHashAsync_WithMatchingHash_ReturnsUser()
    {
        // Arrange
        var tenant = CreateTenant();
        await _fixture.DbContext.Tenants.AddAsync(tenant);
        await _fixture.DbContext.SaveChangesAsync();

        var emailHash = $"hash_{Guid.NewGuid():N}";
        var user = new User
        {
            Id = UuidV7Generator.NewGuid(),
            TenantId = tenant.Id,
            Email = "hash-test@example.com",
            EmailHash = emailHash,
            Status = UserStatus.Active,
            IsEmailVerified = true,
            CreatedAt = DateTimeOffset.UtcNow,
            UpdatedAt = DateTimeOffset.UtcNow,
        };

        var repo = CreateRepository();
        await repo.AddAsync(user);

        // Act
        var found = await repo.FindByEmailHashAsync(emailHash, tenant.Id);

        // Assert
        found.Should().NotBeNull();
        found!.EmailHash.Should().Be(emailHash);
    }

    [Fact]
    public async Task FindByEmailHashAsync_WithWrongTenant_ReturnsNull()
    {
        // Arrange
        var tenant1 = CreateTenant();
        var tenant2 = CreateTenant();
        await _fixture.DbContext.Tenants.AddRangeAsync(tenant1, tenant2);
        await _fixture.DbContext.SaveChangesAsync();

        var emailHash = $"isolation_{Guid.NewGuid():N}";
        var user = CreateUser(tenant1.Id, "isolation@example.com");
        user.EmailHash = emailHash;

        var repo = CreateRepository();
        await repo.AddAsync(user);

        // Act - search in the wrong tenant
        var found = await repo.FindByEmailHashAsync(emailHash, tenant2.Id);

        // Assert - tenant isolation must prevent cross-tenant access
        found.Should().BeNull();
    }

    [Fact]
    public async Task IncrementFailedLoginAttemptsAsync_IncrementsCounter()
    {
        // Arrange
        var tenant = CreateTenant();
        await _fixture.DbContext.Tenants.AddAsync(tenant);
        await _fixture.DbContext.SaveChangesAsync();

        var repo = CreateRepository();
        var user = CreateUser(tenant.Id, $"lockme_{Guid.NewGuid():N}@example.com");
        user.FailedLoginAttempts = 0;
        await repo.AddAsync(user);

        // Act
        await repo.IncrementFailedLoginAttemptsAsync(user.Id);
        _fixture.DbContext.ChangeTracker.Clear();
        var updated = await repo.GetByIdAsync(user.Id);

        // Assert
        updated!.FailedLoginAttempts.Should().Be(1);
    }

    [Fact]
    public async Task ExistsAsync_WithMatchingPredicate_ReturnsTrue()
    {
        var tenant = CreateTenant();
        await _fixture.DbContext.Tenants.AddAsync(tenant);
        await _fixture.DbContext.SaveChangesAsync();

        var repo = CreateRepository();
        var user = CreateUser(tenant.Id, $"exists_{Guid.NewGuid():N}@example.com");
        await repo.AddAsync(user);

        var exists = await repo.ExistsAsync(u => u.Id == user.Id);
        exists.Should().BeTrue();
    }
}
