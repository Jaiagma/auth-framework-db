# Cost Analysis and Optimization Guide

This guide provides cost estimates for running the Auth Framework API on Azure and
strategies for managing and reducing cloud spend.

---

## Table of Contents

1. [Resource Cost Breakdown](#resource-cost-breakdown)
2. [Monthly Cost Estimates](#monthly-cost-estimates)
3. [Cost Optimization Strategies](#cost-optimization-strategies)
4. [Reserved Instances](#reserved-instances)
5. [Auto-Shutdown for Dev Environments](#auto-shutdown-for-dev-environments)
6. [Azure Cost Management Setup](#azure-cost-management-setup)
7. [Budget Alerts](#budget-alerts)

---

## Resource Cost Breakdown

All prices are approximate USD estimates based on East US 2 pricing (pay-as-you-go).
Actual costs vary by region, usage, and negotiated discounts.

### Development Environment

| Resource | SKU / Config | Est. Monthly Cost |
|---|---|---|
| App Service Plan | B2 (2 vCore, 3.5 GB) | $75 |
| App Service | 1 instance, always-on | included |
| PostgreSQL Flexible Server | Standard_B1ms, 16 GB storage | $30 |
| Azure Container Registry | Basic SKU | $5 |
| Key Vault | Standard, ~100 operations/day | $2 |
| Application Insights | ~500 MB/month ingestion | $5 |
| Log Analytics Workspace | 1 GB/day, 30-day retention | $8 |
| Virtual Network | No charge for VNet itself | $0 |
| Bandwidth | ~10 GB egress | $1 |
| **Total (Dev)** | | **~$126/month** |

### Staging Environment

| Resource | SKU / Config | Est. Monthly Cost |
|---|---|---|
| App Service Plan | P0v3 (1 vCore, 4 GB) | $73 |
| App Service | 1–2 instances | included |
| PostgreSQL Flexible Server | Standard_D2s_v3, 32 GB storage | $125 |
| Azure Container Registry | Standard SKU (shared with prod) | included |
| Key Vault | Standard | $5 |
| Application Insights | ~1 GB/month ingestion | $9 |
| Log Analytics Workspace | 2 GB/day, 30-day retention | $15 |
| Private Endpoints | 3 endpoints × $7.30 | $22 |
| **Total (Staging)** | | **~$249/month** |

### Production Environment

| Resource | SKU / Config | Est. Monthly Cost |
|---|---|---|
| App Service Plan | P1v3 (2 vCore, 8 GB) | $146 |
| App Service | 2–10 instances (avg 3) | $219 |
| PostgreSQL Flexible Server | Standard_D2s_v3, 32 GB, HA | $304 |
| Azure Container Registry | Premium SKU | $50 |
| Key Vault | Standard, ~10,000 ops/day | $10 |
| Application Insights | ~5 GB/month ingestion | $45 |
| Log Analytics Workspace | 10 GB/day, 90-day retention | $250 |
| Azure Front Door | Standard (5M requests/month) | $55 |
| Private Endpoints | 5 endpoints | $37 |
| Azure Cache for Redis | Standard C1 | $68 |
| Bandwidth | ~100 GB egress | $9 |
| **Total (Production)** | | **~$1,193/month** |

---

## Monthly Cost Estimates Summary

| Environment | Monthly (Pay-as-you-go) | Monthly (1-yr Reserved) | Monthly (3-yr Reserved) |
|---|---|---|---|
| Development | ~$126 | ~$95 | ~$75 |
| Staging | ~$249 | ~$180 | ~$145 |
| Production | ~$1,193 | ~$850 | ~$680 |
| **Total (all envs)** | **~$1,568** | **~$1,125** | **~$900** |

---

## Cost Optimization Strategies

### 1. Right-Size App Service Plan

Monitor actual CPU and memory utilization over 2–4 weeks before selecting a tier:

```bash
# Check average CPU over the past 7 days
az monitor metrics list \
  --resource "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Web/serverfarms/asp-auth-framework-prod" \
  --metric "CpuPercentage" \
  --interval P1D \
  --start-time "$(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  --aggregation Average \
  --output table
```

If average CPU is consistently below 20%, consider dropping to a smaller SKU.

### 2. Log Analytics Ingestion Cost Control

Log Analytics pricing is driven by data ingestion volume. Reduce costs by:

- Setting the minimum Serilog log level to `Warning` in production for noisy namespaces
- Using sampling in Application Insights for high-volume request telemetry
- Using the **Basic log tier** for verbose diagnostic logs (costs $0.50/GB vs $2.30/GB)

```json
{
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.EntityFrameworkCore.Database.Command": "Warning",
        "Microsoft.AspNetCore.Hosting": "Warning"
      }
    }
  }
}
```

### 3. Use Spot Instances for Dev/Test

App Service Environments (ASEv3) support spot pricing. Alternatively, use Azure
Container Instances with spot pricing for batch migration jobs.

### 4. Delete Unused Resources

```bash
# List resources sorted by type to identify unused items
az resource list \
  --resource-group "rg-auth-framework-dev" \
  --output table \
  --query "sort_by(@, &type)[].{Name:name, Type:type, Location:location}"

# Delete a specific unused resource
az resource delete \
  --ids "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-auth-framework-dev/providers/Microsoft.Cache/Redis/redis-old"
```

### 5. Compress Log Analytics Exports

Archive old logs to Azure Storage (cool tier) instead of keeping them in Log Analytics:

```bash
# Configure data export to storage account (significantly cheaper for long-term retention)
az monitor log-analytics workspace data-export create \
  --name "archive-export" \
  --workspace-name "log-auth-framework-prod" \
  --resource-group "$RESOURCE_GROUP" \
  --tables AppRequests AppDependencies AppExceptions \
  --destination "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Storage/storageAccounts/$STORAGE_ACCOUNT"
```

---

## Reserved Instances

Azure Reserved Instances (1-year or 3-year commitment) offer 30–50% savings over
pay-as-you-go for predictable workloads.

### Purchase a Reservation for App Service

```bash
# List available reservations for App Service
az reservations catalog show \
  --service "app-service" \
  --location "eastus2"
```

Via portal: **Cost Management + Billing → Reservations → Add**

**Reservation recommendations:**

| Resource | Commitment | Savings |
|---|---|---|
| App Service Plan P1v3 (3 instances) | 1-year | ~30% |
| App Service Plan P1v3 (3 instances) | 3-year | ~48% |
| PostgreSQL D2s_v3 | 1-year | ~35% |
| PostgreSQL D2s_v3 | 3-year | ~53% |

> **Tip:** Purchase reservations only after at least 2–4 weeks of live traffic to
> accurately predict your steady-state instance count.

---

## Auto-Shutdown for Dev Environments

Development environments should not run 24/7. Use scheduled shutdown to stop App
Service and PostgreSQL after business hours.

### Stop App Service on a Schedule

```bash
# Create an Automation Account runbook or use Azure Logic Apps
# Simple approach: Azure CLI in a scheduled task or GitHub Actions cron

# Stop dev App Service every night at 8 PM UTC
az webapp stop \
  --name "app-auth-framework-dev" \
  --resource-group "rg-auth-framework-dev"

# Stop dev PostgreSQL every night at 8 PM UTC
az postgres flexible-server stop \
  --name "psql-auth-framework-dev" \
  --resource-group "rg-auth-framework-dev"

# Start them in the morning at 7 AM UTC
az webapp start --name "app-auth-framework-dev" --resource-group "rg-auth-framework-dev"
az postgres flexible-server start --name "psql-auth-framework-dev" --resource-group "rg-auth-framework-dev"
```

Automate this with a GitHub Actions workflow on a schedule:

```yaml
name: Dev Environment Auto-Shutdown

on:
  schedule:
    - cron: '0 20 * * 1-5'  # 8 PM UTC, Mon–Fri (shutdown)
    - cron: '0 7 * * 1-5'   # 7 AM UTC, Mon–Fri (startup)

jobs:
  manage-dev:
    runs-on: ubuntu-latest
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS_DEV }}
      - name: Stop or Start Dev Resources
        run: |
          if [[ "$(date -u +%H)" == "20" ]]; then
            az webapp stop -n app-auth-framework-dev -g rg-auth-framework-dev
            az postgres flexible-server stop -n psql-auth-framework-dev -g rg-auth-framework-dev
          else
            az webapp start -n app-auth-framework-dev -g rg-auth-framework-dev
            az postgres flexible-server start -n psql-auth-framework-dev -g rg-auth-framework-dev
          fi
```

---

## Azure Cost Management Setup

### Enable Cost Analysis

```bash
# View current month spend for the resource group
az consumption usage list \
  --billing-period-name "$(date +%Y%m)01" \
  --query "[?resourceGroup=='rg-auth-framework-prod']" \
  --output table

# View daily costs for the resource group over the past 7 days
az costmanagement query \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --type Usage \
  --dataset-filter '{
    "and": [
      {"dimensions": {"name": "ResourceGroupName", "operator": "In", "values": ["rg-auth-framework-prod"]}}
    ]
  }' \
  --timeframe Last7Days
```

### Export Cost Data

```bash
# Create a monthly cost export to blob storage
az costmanagement export create \
  --name "monthly-cost-export-prod" \
  --scope "/subscriptions/$SUBSCRIPTION_ID" \
  --type Usage \
  --recurrence Monthly \
  --recurrence-period from="$(date +%Y-%m-01)" \
  --storage-account-id "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-cost-mgmt/providers/Microsoft.Storage/storageAccounts/stcostexports" \
  --storage-container "cost-exports" \
  --storage-directory "auth-framework/prod"
```

---

## Budget Alerts

Set budget alerts to receive notifications before exceeding spending thresholds.

### Create Monthly Budgets

```bash
# Production budget: alert at 80% and 100% of $1,500/month
az consumption budget create \
  --budget-name "budget-prod-monthly" \
  --amount 1500 \
  --category Cost \
  --time-grain Monthly \
  --time-period start="$(date +%Y-%m-01)" \
  --resource-group "$RESOURCE_GROUP" \
  --notifications '[
    {
      "enabled": true,
      "operator": "GreaterThanOrEqualTo",
      "threshold": 80,
      "contactEmails": ["finops@example.com"],
      "contactRoles": ["Owner"],
      "thresholdType": "Actual"
    },
    {
      "enabled": true,
      "operator": "GreaterThanOrEqualTo",
      "threshold": 100,
      "contactEmails": ["finops@example.com", "oncall@example.com"],
      "contactRoles": ["Owner"],
      "thresholdType": "Actual"
    },
    {
      "enabled": true,
      "operator": "GreaterThanOrEqualTo",
      "threshold": 110,
      "contactEmails": ["finops@example.com"],
      "thresholdType": "Forecasted"
    }
  ]'

# Development budget: alert at 100% of $200/month
az consumption budget create \
  --budget-name "budget-dev-monthly" \
  --amount 200 \
  --category Cost \
  --time-grain Monthly \
  --time-period start="$(date +%Y-%m-01)" \
  --resource-group "rg-auth-framework-dev" \
  --notifications '[
    {
      "enabled": true,
      "operator": "GreaterThanOrEqualTo",
      "threshold": 100,
      "contactEmails": ["dev-team@example.com"],
      "thresholdType": "Actual"
    }
  ]'
```

### List and Manage Budgets

```bash
# List all budgets for the subscription
az consumption budget list --output table

# Show details of a specific budget
az consumption budget show --budget-name "budget-prod-monthly"

# Delete a budget
az consumption budget delete --budget-name "budget-prod-monthly"
```
