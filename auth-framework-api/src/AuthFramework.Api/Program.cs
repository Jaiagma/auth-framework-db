using System.Text;
using System.Threading.RateLimiting;
using AuthFramework.Api.Middleware;
using AuthFramework.Core.Constants;
using AuthFramework.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

// ─── Serilog ───────────────────────────────────────────────────────────────
Log.Logger = new LoggerConfiguration()
    .ReadFrom.Configuration(builder.Configuration)
    .Enrich.FromLogContext()
    .CreateLogger();

builder.Host.UseSerilog();

// ─── Infrastructure / Services ─────────────────────────────────────────────
builder.Services.AddInfrastructure(builder.Configuration);

// ─── Controllers ───────────────────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();

// ─── Swagger / OpenAPI ─────────────────────────────────────────────────────
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "AuthFramework API",
        Version = "v1",
        Description = "Multi-tenant authentication framework REST API",
        Contact = new OpenApiContact { Name = "AuthFramework", Email = "support@authframework.example.com" },
        License = new OpenApiLicense { Name = "MIT" },
    });

    var securityScheme = new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Description = "Enter 'Bearer {token}'",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer",
        BearerFormat = "JWT",
        Reference = new OpenApiReference { Id = JwtBearerDefaults.AuthenticationScheme, Type = ReferenceType.SecurityScheme },
    };

    options.AddSecurityDefinition(JwtBearerDefaults.AuthenticationScheme, securityScheme);
    options.AddSecurityRequirement(new OpenApiSecurityRequirement { { securityScheme, Array.Empty<string>() } });

    var xmlFiles = Directory.GetFiles(AppContext.BaseDirectory, "*.xml");
    foreach (var xmlFile in xmlFiles)
        options.IncludeXmlComments(xmlFile, includeControllerXmlComments: true);
});

// ─── Authentication / JWT ───────────────────────────────────────────────────
var jwtSection = builder.Configuration.GetSection("JwtSettings");
var secretKey = jwtSection["SecretKey"] ?? throw new InvalidOperationException("JwtSettings:SecretKey missing");

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(secretKey)),
            ValidateIssuer = true,
            ValidIssuer = jwtSection["Issuer"] ?? AuthConstants.Issuer,
            ValidateAudience = true,
            ValidAudience = jwtSection["Audience"] ?? AuthConstants.Issuer,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(30),
        };

        options.Events = new JwtBearerEvents
        {
            OnAuthenticationFailed = ctx =>
            {
                if (ctx.Exception is SecurityTokenExpiredException)
                    ctx.Response.Headers.Append("X-Token-Expired", "true");
                return Task.CompletedTask;
            },
        };
    });

// ─── Authorization ─────────────────────────────────────────────────────────
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(PolicyNames.AdminOnly, policy =>
        policy.RequireAuthenticatedUser().RequireClaim("role", "admin", "superadmin"));
    options.AddPolicy(PolicyNames.SuperAdmin, policy =>
        policy.RequireAuthenticatedUser().RequireClaim("role", "superadmin"));
    options.AddPolicy(PolicyNames.TenantAdmin, policy =>
        policy.RequireAuthenticatedUser().RequireClaim("role", "admin", "superadmin"));
    options.AddPolicy(PolicyNames.VerifiedEmail, policy =>
        policy.RequireAuthenticatedUser().RequireClaim("email_verified", "true"));
});

// ─── CORS ───────────────────────────────────────────────────────────────────
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
builder.Services.AddCors(options =>
    options.AddPolicy("DefaultCors", policy =>
        policy.WithOrigins(allowedOrigins)
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials()));

// ─── Rate Limiting ──────────────────────────────────────────────────────────
var loginMaxAttempts = builder.Configuration.GetValue<int>("RateLimiting:LoginMaxAttempts", 5);
var loginWindowSeconds = builder.Configuration.GetValue<int>("RateLimiting:LoginWindowSeconds", 300);
var globalRpm = builder.Configuration.GetValue<int>("RateLimiting:GlobalRequestsPerMinute", 100);

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;

    options.AddSlidingWindowLimiter("login", limiterOptions =>
    {
        limiterOptions.PermitLimit = loginMaxAttempts;
        limiterOptions.Window = TimeSpan.FromSeconds(loginWindowSeconds);
        limiterOptions.SegmentsPerWindow = 5;
        limiterOptions.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        limiterOptions.QueueLimit = 0;
    });

    options.AddSlidingWindowLimiter("global", limiterOptions =>
    {
        limiterOptions.PermitLimit = globalRpm;
        limiterOptions.Window = TimeSpan.FromMinutes(1);
        limiterOptions.SegmentsPerWindow = 6;
        limiterOptions.QueueProcessingOrder = QueueProcessingOrder.OldestFirst;
        limiterOptions.QueueLimit = 0;
    });
});

// ─── Health Checks ──────────────────────────────────────────────────────────
builder.Services.AddHealthChecks()
    .AddNpgSql(
        connectionString: builder.Configuration.GetConnectionString("DefaultConnection") ?? string.Empty,
        name: "postgres",
        tags: ["db", "readiness"]);

// ─── Build App ──────────────────────────────────────────────────────────────
var app = builder.Build();

// ─── Middleware Pipeline ─────────────────────────────────────────────────────
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseMiddleware<CorrelationIdMiddleware>();
app.UseMiddleware<AuditLoggingMiddleware>();

app.UseSerilogRequestLogging();
app.UseRateLimiter();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "AuthFramework API v1");
        c.RoutePrefix = string.Empty;
    });
}

app.UseHttpsRedirection();
app.UseCors("DefaultCors");
app.UseAuthentication();
app.UseMiddleware<TenantMiddleware>();
app.UseAuthorization();

app.MapControllers();
app.MapHealthChecks("/health");
app.MapHealthChecks("/health/ready", new Microsoft.AspNetCore.Diagnostics.HealthChecks.HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("readiness"),
});

try
{
    Log.Information("Starting AuthFramework API");
    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "AuthFramework API terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

// Expose for integration tests
public partial class Program { }
