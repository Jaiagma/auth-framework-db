# Azure Performance Optimization Guide

This guide covers performance tuning for the Auth Framework API on Azure, from
infrastructure tier selection through to database query optimization.

---

## Table of Contents

1. [App Service Tier Selection](#app-service-tier-selection)
2. [PostgreSQL SKU Selection and Optimization](#postgresql-sku-selection-and-optimization)
3. [Connection Pooling](#connection-pooling)
4. [Caching Strategies](#caching-strategies)
5. [Auto-Scaling Configuration](#auto-scaling-configuration)
6. [CDN Setup](#cdn-setup)
7. [Database Query Optimization](#database-query-optimization)

---

## App Service Tier Selection

### Comparison Table

| SKU | vCores | RAM | Storage | Auto-Scale | Custom Domains | Slots | Use Case |
|---|---|---|---|---|---|---|---|
| **B1** | 1 | 1.75 GB | 10 GB | No | Yes | 0 | Dev experiments |
| **B2** | 2 | 3.5 GB | 10 GB | No | Yes | 0 | Dev/Test |
| **B3** | 4 | 7 GB | 10 GB | No | Yes | 0 | Dev/Test (higher load) |
| **P0v3** | 1 | 4 GB | 250 GB | Yes | Yes | 5 | Low-traffic staging |
| **P1v3** | 2 | 8 GB | 250 GB | Yes | Yes | 5 | Production (standard) |
| **P2v3** | 4 | 16 GB | 250 GB | Yes | Yes | 20 | Production (high load) |
| **P3v3** | 8 | 32 GB | 250 GB | Yes | Yes | 20 | Production (heavy) |
| **P1mv3** | 2 | 16 GB | 250 GB | Yes | Yes | 5 | Memory-intensive workloads |

### Recommendations

- **Development**: Use B2 with a single instance. Avoid costs of Always On.
- **Staging**: Use P0v3 to match the production tier family and validate performance.
- **Production (baseline)**: P1v3 with auto-scale from 2–10 instances.
- **Production (auth-heavy)**: Consider P1mv3 if JWT signing/verification is a bottleneck.

### Change App Service Plan SKU

```bash
# Scale up App Service Plan
az appservice plan update \
  --name "asp-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --sku P2v3

# Scale out manually
az appservice plan update \
  --name "asp-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --number-of-workers 4
```

---

## PostgreSQL SKU Selection and Optimization

### SKU Comparison Table

| Tier | SKU | vCores | RAM | IOPS | Use Case |
|---|---|---|---|---|---|
| Burstable | Standard_B1ms | 1 | 2 GB | 640 | Dev/Test |
| Burstable | Standard_B2s | 2 | 4 GB | 1,280 | Small staging |
| General Purpose | Standard_D2s_v3 | 2 | 8 GB | 3,200 | Production (baseline) |
| General Purpose | Standard_D4s_v3 | 4 | 16 GB | 6,400 | Production (medium load) |
| General Purpose | Standard_D8s_v3 | 8 | 32 GB | 12,800 | Production (high load) |
| Memory Optimized | Standard_E2s_v3 | 2 | 16 GB | 3,200 | Read-heavy, large working set |
| Memory Optimized | Standard_E4s_v3 | 4 | 32 GB | 6,400 | Heavy analytics |

### PostgreSQL Server Parameter Tuning

```bash
# Increase shared_buffers (set to ~25% of server RAM)
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "shared_buffers" \
  --value "2097152"  # 2 GB in 8KB pages for 8GB RAM server

# Set effective_cache_size (estimate of OS + PG cache, ~75% of RAM)
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "effective_cache_size" \
  --value "6291456"  # 6 GB

# Increase work_mem for complex query operations
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "work_mem" \
  --value "65536"  # 64 MB

# Set max_connections appropriately
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "max_connections" \
  --value "200"
```

---

## Connection Pooling

Opening a new database connection is expensive (~50ms). With multiple App Service
instances each holding a pool, the total connection count can grow quickly. Use connection
pooling to cap the total connections to PostgreSQL.

### NpgSql Connection Pool Configuration

NpgSql has a built-in connection pool. Configure it via the connection string:

```
Host=...;Database=authdb;Username=...;Password=...;
Maximum Pool Size=20;Minimum Pool Size=2;
Connection Idle Lifetime=300;Connection Pruning Interval=10;
Ssl Mode=Require
```

Configure in `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "DefaultConnection": "@Microsoft.KeyVault(VaultName=kv-auth-framework-prod;SecretName=postgres-connection-string)"
  },
  "DatabaseOptions": {
    "MaxPoolSize": 20,
    "MinPoolSize": 2,
    "ConnectionIdleLifetime": 300
  }
}
```

Configure in `Program.cs`:

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
{
    var connectionString = builder.Configuration.GetConnectionString("DefaultConnection");
    options.UseNpgsql(connectionString, npgsql =>
    {
        npgsql.CommandTimeout(30);
        npgsql.EnableRetryOnFailure(
            maxRetryCount: 3,
            maxRetryDelay: TimeSpan.FromSeconds(5),
            errorCodesToAdd: null);
    });
});
```

### PgBouncer (Recommended for High-Scale Deployments)

For high-scale scenarios (many App Service instances, high concurrency), deploy PgBouncer
in transaction-pooling mode as a sidecar or separate container.

With 10 App Service instances each holding a pool of 20, you have up to 200 connections
to PostgreSQL. With PgBouncer, you can cap PostgreSQL connections at 50 while serving
many more application-level connections.

**PgBouncer configuration (`pgbouncer.ini`):**

```ini
[databases]
authdb = host=psql-auth-framework-prod.postgres.database.azure.com dbname=authdb

[pgbouncer]
listen_port = 5432
listen_addr = 0.0.0.0
auth_type = scram-sha-256
pool_mode = transaction
max_client_conn = 500
default_pool_size = 50
min_pool_size = 5
server_idle_timeout = 600
client_idle_timeout = 300
```

Update the application connection string to point to PgBouncer:

```
Host=pgbouncer-container;Port=5432;Database=authdb;...;No Reset On Close=true
```

> **Note:** In transaction-pooling mode, avoid `SET LOCAL` commands as session state
> is not preserved. Use explicit schema operations or application-level context passing.

---

## Caching Strategies

### In-Memory Caching (Single Instance)

Suitable for development and low-traffic scenarios:

```csharp
builder.Services.AddMemoryCache(options =>
{
    options.SizeLimit = 500; // Maximum 500 entries
});
```

### Azure Cache for Redis (Distributed Cache)

Required when running multiple App Service instances to maintain cache consistency:

```bash
# Provision Redis Cache
az redis create \
  --name "redis-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard \
  --vm-size C1 \
  --enable-non-ssl-port false
```

```csharp
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration["Redis:ConnectionString"];
    options.InstanceName = "authfw:";
});
```

### Cache-Aside Pattern

```csharp
public async Task<UserDto?> GetUserByIdAsync(Guid userId)
{
    var cacheKey = $"user:{userId}";

    // Try cache first
    var cached = await _cache.GetStringAsync(cacheKey);
    if (cached is not null)
        return JsonSerializer.Deserialize<UserDto>(cached);

    // Cache miss — fetch from DB
    var user = await _dbContext.Users
        .AsNoTracking()
        .FirstOrDefaultAsync(u => u.Id == userId);

    if (user is not null)
    {
        await _cache.SetStringAsync(
            cacheKey,
            JsonSerializer.Serialize(user.ToDto()),
            new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(15)
            });
    }

    return user?.ToDto();
}
```

---

## Auto-Scaling Configuration

```bash
# Create auto-scale rule: scale out when CPU > 70% for 5 minutes
az monitor autoscale create \
  --resource-group "$RESOURCE_GROUP" \
  --name "autoscale-auth-framework-prod" \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/serverfarms/asp-auth-framework-prod" \
  --min-count 2 \
  --max-count 10 \
  --count 2

az monitor autoscale rule create \
  --resource-group "$RESOURCE_GROUP" \
  --autoscale-name "autoscale-auth-framework-prod" \
  --condition "CpuPercentage > 70 avg 5m" \
  --scale out 2 \
  --cooldown 5

# Scale in when CPU < 30% for 10 minutes
az monitor autoscale rule create \
  --resource-group "$RESOURCE_GROUP" \
  --autoscale-name "autoscale-auth-framework-prod" \
  --condition "CpuPercentage < 30 avg 10m" \
  --scale in 1 \
  --cooldown 10
```

---

## CDN Setup

While the Auth Framework API is primarily a REST API, static assets (OpenAPI docs,
Swagger UI) can benefit from CDN caching.

```bash
# Create a CDN profile
az cdn profile create \
  --name "cdn-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --sku Standard_Microsoft

# Create a CDN endpoint pointing to the App Service
az cdn endpoint create \
  --name "api-auth-framework" \
  --profile-name "cdn-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --origin "$APP_SERVICE_NAME.azurewebsites.net" \
  --origin-host-header "$APP_SERVICE_NAME.azurewebsites.net" \
  --enable-compression true \
  --no-http false \
  --no-https false
```

For APIs, consider using Azure Front Door with caching rules instead of CDN for better
WAF integration and global routing.

---

## Database Query Optimization

### Index Strategy

Key indexes are defined in `indexes.sql`. Ensure these cover the most common query
patterns:

```sql
-- Covering index for user lookups by email (most common auth query)
CREATE UNIQUE INDEX CONCURRENTLY idx_users_email
  ON users (lower(email));

-- Index for token lookups
CREATE INDEX CONCURRENTLY idx_refresh_tokens_user_id_expires
  ON refresh_tokens (user_id, expires_at)
  WHERE revoked_at IS NULL;

-- Partial index for active sessions only
CREATE INDEX CONCURRENTLY idx_sessions_active
  ON sessions (user_id, created_at DESC)
  WHERE expires_at > NOW();
```

### Query Analysis

```sql
-- Find slow queries (requires pg_stat_statements extension)
SELECT
    query,
    calls,
    total_exec_time / calls AS avg_ms,
    rows / calls AS avg_rows,
    stddev_exec_time AS stddev_ms
FROM pg_stat_statements
WHERE calls > 100
ORDER BY avg_ms DESC
LIMIT 20;

-- Check for missing indexes (sequential scans on large tables)
SELECT
    schemaname,
    tablename,
    seq_scan,
    idx_scan,
    n_live_tup
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan
  AND n_live_tup > 10000
ORDER BY seq_scan DESC;
```

### Enable `pg_stat_statements`

```bash
az postgres flexible-server parameter set \
  --name "$PG_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --parameter-name "azure.extensions" \
  --value "pg_stat_statements,pg_audit"
```

### EF Core Query Optimization

```csharp
// Use AsNoTracking for read-only queries
var users = await _dbContext.Users
    .AsNoTracking()
    .Where(u => u.TenantId == tenantId && u.IsActive)
    .Select(u => new UserDto { Id = u.Id, Email = u.Email })  // project, don't load entire entity
    .ToListAsync();

// Use compiled queries for high-frequency paths
private static readonly Func<AppDbContext, Guid, Task<User?>> _getUserById =
    EF.CompileAsyncQuery((AppDbContext ctx, Guid id) =>
        ctx.Users.AsNoTracking().FirstOrDefault(u => u.Id == id));

var user = await _getUserById(_dbContext, userId);

// Avoid N+1 queries with Include
var usersWithRoles = await _dbContext.Users
    .AsNoTracking()
    .Include(u => u.Roles)
    .Where(u => u.TenantId == tenantId)
    .ToListAsync();
```
