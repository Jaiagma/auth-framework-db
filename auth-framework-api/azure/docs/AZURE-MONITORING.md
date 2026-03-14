# Monitoring and Logging Guide

This guide covers the full observability stack for the Auth Framework API on Azure:
Application Insights, Serilog, Log Analytics, alerting, dashboards, health checks, and
distributed tracing.

---

## Table of Contents

1. [Application Insights Setup](#application-insights-setup)
2. [Serilog Configuration](#serilog-configuration)
3. [Log Analytics Workspace Queries](#log-analytics-workspace-queries)
4. [Alert Configuration](#alert-configuration)
5. [Dashboard Setup](#dashboard-setup)
6. [Health Checks](#health-checks)
7. [Distributed Tracing](#distributed-tracing)

---

## Application Insights Setup

### Provisioning

Application Insights is provisioned by the monitoring Terraform module. It is linked to
the Log Analytics workspace (workspace-based resource), which gives 90-day retention
and unified querying.

```bash
# Retrieve the connection string for use in app configuration
APP_INSIGHTS_CONN=$(az monitor app-insights component show \
  --app "appi-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --query connectionString \
  --output tsv)

echo "$APP_INSIGHTS_CONN"
```

### SDK Configuration in .NET 9

Install the NuGet packages:

```bash
dotnet add package Microsoft.ApplicationInsights.AspNetCore
dotnet add package Microsoft.ApplicationInsights.WorkerService
```

Configure in `Program.cs`:

```csharp
var builder = WebApplication.CreateBuilder(args);

// Application Insights — reads APPLICATIONINSIGHTS_CONNECTION_STRING from env/config
builder.Services.AddApplicationInsightsTelemetry();

// Customize telemetry
builder.Services.Configure<TelemetryConfiguration>(config =>
{
    config.TelemetryProcessorChainBuilder
        .Use(next => new HealthCheckTelemetryFilter(next))
        .Build();
});
```

Create a custom telemetry filter to suppress noisy health check requests:

```csharp
public class HealthCheckTelemetryFilter : ITelemetryProcessor
{
    private readonly ITelemetryProcessor _next;

    public HealthCheckTelemetryFilter(ITelemetryProcessor next) => _next = next;

    public void Process(ITelemetry item)
    {
        if (item is RequestTelemetry request &&
            request.Url.AbsolutePath.StartsWith("/health"))
        {
            return; // Drop health check telemetry
        }

        _next.Process(item);
    }
}
```

### Custom Telemetry

```csharp
// Inject TelemetryClient for custom events and metrics
public class AuthService
{
    private readonly TelemetryClient _telemetry;

    public AuthService(TelemetryClient telemetry) => _telemetry = telemetry;

    public async Task<LoginResult> LoginAsync(string email)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            var result = await PerformLoginAsync(email);

            _telemetry.TrackEvent("UserLogin", new Dictionary<string, string>
            {
                ["UserId"] = result.UserId.ToString(),
                ["Method"] = "password"
            });

            _telemetry.TrackMetric("LoginDurationMs", sw.ElapsedMilliseconds);
            return result;
        }
        catch (Exception ex)
        {
            _telemetry.TrackException(ex, new Dictionary<string, string>
            {
                ["Email"] = email,
                ["Operation"] = "Login"
            });
            throw;
        }
    }
}
```

---

## Serilog Configuration

### NuGet Packages

```bash
dotnet add package Serilog.AspNetCore
dotnet add package Serilog.Sinks.ApplicationInsights
dotnet add package Serilog.Sinks.Console
dotnet add package Serilog.Enrichers.Environment
dotnet add package Serilog.Enrichers.Thread
dotnet add package Serilog.Enrichers.Process
```

### Configuration in `appsettings.json`

```json
{
  "Serilog": {
    "Using": ["Serilog.Sinks.Console", "Serilog.Sinks.ApplicationInsights"],
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.Hosting.Lifetime": "Information",
        "System": "Warning"
      }
    },
    "WriteTo": [
      {
        "Name": "Console",
        "Args": {
          "outputTemplate": "[{Timestamp:HH:mm:ss} {Level:u3}] {SourceContext}: {Message:lj}{NewLine}{Exception}"
        }
      },
      {
        "Name": "ApplicationInsights",
        "Args": {
          "telemetryConverter": "Serilog.Sinks.ApplicationInsights.TelemetryConverters.TraceTelemetryConverter, Serilog.Sinks.ApplicationInsights"
        }
      }
    ],
    "Enrich": ["FromLogContext", "WithMachineName", "WithThreadId", "WithProcessId"],
    "Properties": {
      "Application": "auth-framework-api",
      "Environment": "Production"
    }
  }
}
```

### Bootstrap Configuration in `Program.cs`

```csharp
// Bootstrap logger captures startup errors before full config is loaded
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    builder.Host.UseSerilog((context, services, config) =>
        config
            .ReadFrom.Configuration(context.Configuration)
            .ReadFrom.Services(services)
            .Enrich.FromLogContext()
            .Enrich.WithProperty("ApplicationVersion",
                Assembly.GetExecutingAssembly().GetName().Version?.ToString())
    );

    // ... configure services

    var app = builder.Build();
    app.UseSerilogRequestLogging(options =>
    {
        options.EnrichDiagnosticContext = (diagnosticContext, httpContext) =>
        {
            diagnosticContext.Set("RequestHost", httpContext.Request.Host.Value);
            diagnosticContext.Set("UserAgent", httpContext.Request.Headers.UserAgent);
            diagnosticContext.Set("UserId", httpContext.User?.FindFirst("sub")?.Value);
        };
    });

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application startup failed");
    return 1;
}
finally
{
    await Log.CloseAndFlushAsync();
}
```

---

## Log Analytics Workspace Queries

These KQL queries can be run in the Azure portal under **Log Analytics > Logs** or via
the Azure CLI using `az monitor log-analytics query`.

### Request Rate and Latency

```kql
// Request count by status code over the last hour
AppRequests
| where TimeGenerated > ago(1h)
| summarize RequestCount = count() by ResultCode
| order by RequestCount desc

// P50, P95, P99 latency by operation
AppRequests
| where TimeGenerated > ago(1h)
| summarize
    P50 = percentile(DurationMs, 50),
    P95 = percentile(DurationMs, 95),
    P99 = percentile(DurationMs, 99)
  by OperationName
| order by P95 desc
```

### Error Analysis

```kql
// Top exceptions in the last 24 hours
AppExceptions
| where TimeGenerated > ago(24h)
| summarize Count = count() by ExceptionType, OuterMessage
| order by Count desc
| take 20

// Failed requests with details
AppRequests
| where TimeGenerated > ago(1h) and Success == false
| project TimeGenerated, OperationName, ResultCode, DurationMs, Url, ExceptionType
| order by TimeGenerated desc
```

### Authentication Events

```kql
// Login attempts by result
AppEvents
| where TimeGenerated > ago(24h) and Name == "UserLogin"
| summarize Count = count() by tostring(Properties.Method)

// Failed login attempts (potential brute force detection)
AppRequests
| where TimeGenerated > ago(1h)
    and OperationName == "POST /auth/login"
    and ResultCode == "401"
| summarize FailedAttempts = count() by ClientIP = tostring(split(Url, "/")[2])
| where FailedAttempts > 10
| order by FailedAttempts desc
```

### Infrastructure Health

```kql
// App Service container events
AppServiceConsoleLogs
| where TimeGenerated > ago(1h)
| where ResultDescription contains "error" or ResultDescription contains "Error"
| project TimeGenerated, ResultDescription
| order by TimeGenerated desc

// Database connection errors
AppDependencies
| where TimeGenerated > ago(1h)
    and Type == "SQL"
    and Success == false
| project TimeGenerated, Name, Data, Duration, ResultCode
| order by TimeGenerated desc
```

---

## Alert Configuration

### Metric Alerts via Azure CLI

```bash
# Alert when average CPU exceeds 80% for 5 minutes
az monitor metrics alert create \
  --name "High CPU Alert" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/serverfarms/asp-auth-framework-prod" \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action "$ACTION_GROUP_ID"

# Alert when HTTP 5xx error rate exceeds 1%
az monitor metrics alert create \
  --name "High 5xx Error Rate" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$APP_SERVICE_NAME" \
  --condition "avg Http5xx > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1 \
  --action "$ACTION_GROUP_ID"

# Alert when average response time exceeds 2 seconds
az monitor metrics alert create \
  --name "Slow Response Time" \
  --resource-group "$RESOURCE_GROUP" \
  --scopes "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/sites/$APP_SERVICE_NAME" \
  --condition "avg AverageResponseTime > 2" \
  --window-size 10m \
  --evaluation-frequency 5m \
  --severity 2 \
  --action "$ACTION_GROUP_ID"
```

### Create Action Group

```bash
az monitor action-group create \
  --name "ag-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --short-name "authfw" \
  --action email "on-call-email" "oncall@example.com" \
  --action webhook "pagerduty" "https://events.pagerduty.com/integration/<key>/enqueue"
```

---

## Dashboard Setup

```bash
# Create an Azure Dashboard from a JSON template
az portal dashboard create \
  --resource-group "$RESOURCE_GROUP" \
  --name "dashboard-auth-framework-prod" \
  --input-path "azure/dashboards/main-dashboard.json" \
  --location "$LOCATION"
```

A sample dashboard template is provided at `azure/dashboards/main-dashboard.json`. It
includes tiles for:
- Request rate (last 24h)
- P95 response latency
- Error rate
- Active users
- Database connection count
- App Service CPU and memory

---

## Health Checks

### ASP.NET Core Health Check Configuration

```csharp
builder.Services.AddHealthChecks()
    .AddNpgSql(
        connectionString: builder.Configuration.GetConnectionString("DefaultConnection")!,
        name: "postgresql",
        failureStatus: HealthStatus.Unhealthy,
        tags: ["db", "postgresql"])
    .AddUrlGroup(
        uri: new Uri("https://api.sendgrid.com"),
        name: "sendgrid",
        failureStatus: HealthStatus.Degraded,
        tags: ["external"])
    .AddApplicationInsightsPublisher();

// Map health check endpoints
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});

app.MapHealthChecks("/health/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("db"),
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});

app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false  // Liveness: always return 200 if app is running
});
```

---

## Distributed Tracing

Application Insights automatically instruments outgoing HTTP calls, EF Core queries, and
Azure SDK calls when using the NuGet SDK. Use `Activity` and `ActivitySource` for custom
spans:

```csharp
private static readonly ActivitySource _activitySource =
    new("AuthFramework.Services.Auth");

public async Task<LoginResult> LoginAsync(string email)
{
    using var activity = _activitySource.StartActivity("AuthService.Login");
    activity?.SetTag("user.email_hash", HashEmail(email));

    using var dbActivity = _activitySource.StartActivity("DB.GetUser");
    var user = await _dbContext.Users.FirstOrDefaultAsync(u => u.Email == email);
    dbActivity?.Stop();

    // ...
}
```

Register the `ActivitySource` with OpenTelemetry:

```csharp
builder.Services.AddOpenTelemetry()
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddEntityFrameworkCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddSource("AuthFramework.Services.*")
        .AddAzureMonitorTraceExporter(options =>
        {
            options.ConnectionString = builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"];
        }));
```

The Application Insights **Application Map** view will show the full dependency graph
including the database and any downstream services, with latency and error rate for each
edge.
