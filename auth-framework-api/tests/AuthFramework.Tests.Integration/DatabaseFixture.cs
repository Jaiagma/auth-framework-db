using AuthFramework.Infrastructure.Data;
using Microsoft.EntityFrameworkCore;
using Testcontainers.PostgreSql;
using Xunit;

namespace AuthFramework.Tests.Integration;

/// <summary>
/// Test fixture that spins up a real PostgreSQL container using Testcontainers
/// and provides an <see cref="AuthDbContext"/> for integration tests.
/// </summary>
public sealed class DatabaseFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container;

    public AuthDbContext DbContext { get; private set; } = null!;
    public string ConnectionString { get; private set; } = string.Empty;

    public DatabaseFixture()
    {
        _container = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .WithDatabase("authframework_test")
            .WithUsername("testuser")
            .WithPassword("testpassword")
            .WithCleanUp(true)
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        ConnectionString = _container.GetConnectionString();

        var options = new DbContextOptionsBuilder<AuthDbContext>()
            .UseNpgsql(ConnectionString)
            .Options;

        DbContext = new AuthDbContext(options);
        await DbContext.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await DbContext.DisposeAsync();
        await _container.StopAsync();
        await _container.DisposeAsync();
    }
}
