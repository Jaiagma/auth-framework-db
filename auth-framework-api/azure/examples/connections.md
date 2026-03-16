# Connection String Reference

This document provides connection string examples for Auth Framework across different environments and client types.

## .NET / Npgsql (appsettings.json)

### Development (local Docker)
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=authframework;Username=authframework;Password=localdev_password;SslMode=Disable"
  }
}
```

### Staging / Production (Azure - direct)
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=authframework-prod-psql.postgres.database.azure.com;Port=5432;Database=authframework;Username=psqladmin;Password=YOUR_PASSWORD;SslMode=VerifyFull"
  }
}
```

### Azure App Service (Key Vault reference)
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "@Microsoft.KeyVault(VaultName=authframework-prod-kv;SecretName=db-connection-string)"
  }
}
```

## libpq / psql / pg_dump

### Connect to Azure PostgreSQL
```bash
psql "host=authframework-prod-psql.postgres.database.azure.com port=5432 dbname=authframework user=psqladmin sslmode=verify-full"
# Or using URI format:
psql "postgresql://psqladmin:PASSWORD@authframework-prod-psql.postgres.database.azure.com:5432/authframework?sslmode=verify-full"
```

### pg_dump (backup)
```bash
pg_dump \
  -h authframework-prod-psql.postgres.database.azure.com \
  -U psqladmin \
  -d authframework \
  --format=custom \
  -f backup.dump
```

## Environment Variables

```bash
# Docker / local
export ConnectionStrings__DefaultConnection="Host=localhost;Port=5432;Database=authframework;Username=authframework;Password=localdev_password;SslMode=Disable"

# Azure (direct)
export ConnectionStrings__DefaultConnection="Host=authframework-prod-psql.postgres.database.azure.com;Port=5432;Database=authframework;Username=psqladmin;Password=YOURPASSWORD;SslMode=VerifyFull"

# Standard DATABASE_URL (compatible with many tools)
export DATABASE_URL="postgresql://psqladmin:YOURPASSWORD@authframework-prod-psql.postgres.database.azure.com:5432/authframework?sslmode=verify-full"
```

## Entity Framework Core

```csharp
// Program.cs
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseNpgsql(
        builder.Configuration.GetConnectionString("DefaultConnection"),
        npgsql => npgsql.EnableRetryOnFailure(maxRetryCount: 3)
    ));
```

## Connection String Parameters Reference

| Parameter      | Development  | Staging/Production            | Notes                          |
|----------------|--------------|-------------------------------|--------------------------------|
| Host           | localhost    | *.postgres.database.azure.com | Azure FQDN                     |
| Port           | 5432         | 5432                          | Standard PostgreSQL port       |
| Database       | authframework | authframework                | Database name                  |
| SslMode        | Disable      | VerifyFull                    | Always use VerifyFull in Azure |
| Timeout        | 30           | 30                            | Connection timeout (seconds)   |
| CommandTimeout | 30           | 30                            | Query timeout (seconds)        |
| MaxPoolSize    | 20           | 100                           | Connection pool max            |
| MinPoolSize    | 1            | 5                             | Connection pool min            |
