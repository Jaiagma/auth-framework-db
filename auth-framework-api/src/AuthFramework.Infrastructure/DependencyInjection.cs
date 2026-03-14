using AuthFramework.Application.Interfaces;
using AuthFramework.Application.Services;
using AuthFramework.Infrastructure.Data;
using AuthFramework.Infrastructure.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace AuthFramework.Infrastructure;

/// <summary>Extension methods for registering infrastructure services with the DI container.</summary>
public static class DependencyInjection
{
    /// <summary>
    /// Registers the database context, repositories, and application services.
    /// </summary>
    public static IServiceCollection AddInfrastructure(this IServiceCollection services, IConfiguration configuration)
    {
        // Database
        var connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' is not configured.");

        services.AddDbContext<AuthDbContext>(options =>
            options.UseNpgsql(connectionString, npgsql =>
            {
                npgsql.EnableRetryOnFailure(maxRetryCount: 3, maxRetryDelay: TimeSpan.FromSeconds(5), errorCodesToAdd: null);
                npgsql.CommandTimeout(30);
            }));

        // Repositories
        services.AddScoped(typeof(IRepository<>), typeof(Repository<>));
        services.AddScoped<IUserRepository, UserRepository>();
        services.AddScoped<ITenantRepository, TenantRepository>();
        services.AddScoped<SessionRepository>();

        // Application Services
        services.AddScoped<ITokenService, TokenService>();
        services.AddScoped<IEncryptionService, EncryptionService>();
        services.AddScoped<IAuditService, AuditService>();
        services.AddScoped<ISessionService, SessionService>();
        services.AddScoped<IAuthenticationService, AuthenticationService>();
        services.AddScoped<IMfaService, MfaService>();
        services.AddScoped<IOAuthService, OAuthService>();
        services.AddScoped<ISsoService, SsoService>();
        services.AddScoped<IFederatedIdentityService, FederatedIdentityService>();
        services.AddScoped<ILocalizationService, LocalizationService>();

        return services;
    }
}
