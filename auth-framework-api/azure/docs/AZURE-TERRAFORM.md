# Azure Terraform Infrastructure Guide

This guide covers the Terraform configuration used to provision and manage all Azure
infrastructure for the Auth Framework API.

---

## Table of Contents

1. [Directory Structure](#directory-structure)
2. [Module Descriptions](#module-descriptions)
3. [State Management](#state-management)
4. [Variable Reference](#variable-reference)
5. [Output Reference](#output-reference)
6. [Common Commands](#common-commands)
7. [Workspace Management](#workspace-management)

---

## Directory Structure

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars.example
│   ├── staging/
│   │   └── (same structure as dev)
│   └── prod/
│       └── (same structure as dev)
│
└── modules/
    ├── app-service/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── postgresql/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── networking/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── key-vault/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── acr/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── monitoring/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

---

## Module Descriptions

### `modules/networking`

Provisions the Virtual Network, subnets, and Network Security Groups.

**Resources created:**
- `azurerm_virtual_network` — main VNet with the address space `10.0.0.0/16`
- `azurerm_subnet` — app, data, pe, and bastion subnets
- `azurerm_network_security_group` — one NSG per subnet
- `azurerm_subnet_network_security_group_association` — attaches NSGs to subnets
- `azurerm_private_dns_zone` — zones for `privatelink.postgres.database.azure.com`,
  `privatelink.vaultcore.azure.net`, `privatelink.azurecr.io`

**Key design decisions:**
- Subnets use distinct address blocks to simplify NSG rules.
- The data subnet is delegated to `Microsoft.DBforPostgreSQL/flexibleServers`.
- The app subnet has `enforce_private_link_service_network_policies` disabled to allow
  VNet integration.

### `modules/postgresql`

Provisions the PostgreSQL Flexible Server, initial database, and administrator password.

**Resources created:**
- `azurerm_postgresql_flexible_server` — the database server
- `azurerm_postgresql_flexible_server_database` — the `authdb` database
- `azurerm_postgresql_flexible_server_configuration` — server-level parameters
- `random_password` — generates a strong admin password
- `azurerm_key_vault_secret` — stores the password in Key Vault

**Key design decisions:**
- The server is VNet-injected (no public endpoint).
- `ssl_enforcement_enabled = true` is set via server parameters.
- `high_availability.mode = "ZoneRedundant"` in production environments.
- Backup retention is set to 35 days in production.

### `modules/app-service`

Provisions the App Service Plan, App Service, deployment slots, and auto-scale settings.

**Resources created:**
- `azurerm_service_plan` — the underlying compute plan
- `azurerm_linux_web_app` — the production application
- `azurerm_linux_web_app_slot` — the staging slot
- `azurerm_app_service_virtual_network_swift_connection` — VNet integration
- `azurerm_monitor_autoscale_setting` — scale rules based on CPU
- `azurerm_role_assignment` — grants the app's managed identity `AcrPull` and
  `Key Vault Secrets User` roles

**Key design decisions:**
- `always_on = true` to prevent cold starts.
- App settings use Key Vault references (`@Microsoft.KeyVault(...)`) rather than
  plain-text secrets.
- The staging slot shares VNet integration and most settings with production.

### `modules/key-vault`

Provisions the Key Vault and configures access policies and private endpoint.

**Resources created:**
- `azurerm_key_vault` — the vault itself
- `azurerm_private_endpoint` — private endpoint in the PE subnet
- `azurerm_private_dns_zone_virtual_network_link` — links private DNS to the VNet
- `azurerm_key_vault_access_policy` — for CI/CD service principal (secret write)

**Key design decisions:**
- `purge_protection_enabled = true` prevents accidental permanent deletion.
- `soft_delete_retention_days = 90` for production.
- Public network access is disabled; the vault is only reachable via private endpoint.

### `modules/acr`

Provisions the Azure Container Registry and private endpoint.

**Resources created:**
- `azurerm_container_registry` — Premium SKU in production
- `azurerm_container_registry_geo_replication` — secondary region (prod only)
- `azurerm_private_endpoint` — private endpoint for image pulls within the VNet

### `modules/monitoring`

Provisions the observability stack.

**Resources created:**
- `azurerm_log_analytics_workspace`
- `azurerm_application_insights` — linked to the Log Analytics workspace
- `azurerm_monitor_diagnostic_setting` — for App Service and PostgreSQL
- `azurerm_monitor_action_group` — email/webhook notification targets
- `azurerm_monitor_metric_alert` — CPU, memory, error-rate, and response-time alerts

---

## State Management

### Backend Configuration

All environments use Azure Blob Storage as the Terraform backend. This provides:
- Shared state accessible to all team members and CI/CD pipelines
- State locking via Azure Blob leases (prevents concurrent modifications)
- Versioning for state history and rollback
- Encryption at rest

Each environment has its own state file at a distinct key:

```hcl
# terraform/environments/prod/backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "stterraformstate1a2b3c4d"
    container_name       = "tfstate"
    key                  = "prod/terraform.tfstate"
  }
}
```

**State keys by environment:**

| Environment | State Key |
|---|---|
| dev | `dev/terraform.tfstate` |
| staging | `staging/terraform.tfstate` |
| prod | `prod/terraform.tfstate` |

### Protecting the State Storage Account

```bash
# Enable delete lock so the storage account cannot be accidentally deleted
az lock create \
  --name "DoNotDelete" \
  --resource-group "rg-terraform-state" \
  --resource-name "stterraformstate1a2b3c4d" \
  --resource-type "Microsoft.Storage/storageAccounts" \
  --lock-type CanNotDelete

# Enable blob versioning (already set during initial setup)
az storage account blob-service-properties update \
  --account-name "stterraformstate1a2b3c4d" \
  --resource-group "rg-terraform-state" \
  --enable-versioning true
```

---

## Variable Reference

### Root Variables (`environments/<env>/variables.tf`)

| Variable | Type | Default | Description |
|---|---|---|---|
| `environment` | string | — | Environment name (`dev`, `staging`, `prod`) |
| `location` | string | `eastus2` | Primary Azure region |
| `secondary_location` | string | `westus2` | Secondary region for geo-redundancy (prod) |
| `resource_group_name` | string | — | Resource group for all resources |
| `app_name` | string | `auth-framework` | Base name used in resource naming |
| `tags` | map(string) | `{}` | Additional tags applied to all resources |

### App Service Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `app_service_sku_name` | string | `B2` | App Service Plan SKU |
| `app_service_min_count` | number | `1` | Minimum instance count for auto-scale |
| `app_service_max_count` | number | `5` | Maximum instance count for auto-scale |
| `container_image_tag` | string | `latest` | Docker image tag to deploy |
| `app_allowed_origins` | list(string) | `[]` | CORS allowed origins |

### PostgreSQL Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `postgres_sku_name` | string | `B_Standard_B1ms` | PostgreSQL Flexible Server SKU |
| `postgres_storage_mb` | number | `32768` | Storage size in MB |
| `postgres_version` | string | `16` | PostgreSQL major version |
| `postgres_admin_username` | string | `pgadmin` | Administrator username |
| `postgres_backup_retention_days` | number | `7` | Backup retention in days |
| `postgres_geo_redundant_backup` | bool | `false` | Enable geo-redundant backups |
| `postgres_high_availability` | bool | `false` | Enable zone-redundant HA |

### Networking Variables

| Variable | Type | Default | Description |
|---|---|---|---|
| `vnet_address_space` | string | `10.0.0.0/16` | VNet CIDR block |
| `app_subnet_prefix` | string | `10.0.1.0/24` | App Service subnet CIDR |
| `data_subnet_prefix` | string | `10.0.2.0/24` | PostgreSQL subnet CIDR |
| `pe_subnet_prefix` | string | `10.0.3.0/24` | Private endpoints subnet CIDR |

---

## Output Reference

| Output | Description |
|---|---|
| `acr_login_server` | FQDN of the Container Registry (e.g., `myacr.azurecr.io`) |
| `acr_name` | Short name of the ACR resource |
| `app_service_name` | Name of the App Service |
| `app_service_default_hostname` | Default hostname (`.azurewebsites.net`) |
| `app_service_principal_id` | Object ID of the system-assigned managed identity |
| `key_vault_name` | Name of the Key Vault |
| `key_vault_uri` | URI of the Key Vault (e.g., `https://kv-xxx.vault.azure.net/`) |
| `postgres_server_name` | Name of the PostgreSQL Flexible Server |
| `postgres_server_fqdn` | Fully qualified domain name of the server |
| `postgres_admin_username` | Administrator username |
| `log_analytics_workspace_id` | Resource ID of the Log Analytics workspace |
| `application_insights_connection_string` | Connection string for the App Insights SDK |
| `vnet_id` | Resource ID of the virtual network |

---

## Common Commands

### Initialize

```bash
cd terraform/environments/prod

# First-time initialization with backend config
terraform init \
  -backend-config="resource_group_name=rg-terraform-state" \
  -backend-config="storage_account_name=stterraformstate1a2b3c4d" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=prod/terraform.tfstate"

# Re-initialize after adding or upgrading providers
terraform init -upgrade
```

### Plan

```bash
# Standard plan saved to file (recommended for production)
terraform plan -var-file="terraform.tfvars" -out="prod.tfplan"

# Plan targeting a specific module
terraform plan -var-file="terraform.tfvars" -target="module.app_service"

# Plan showing only destroy operations
terraform plan -destroy -var-file="terraform.tfvars"
```

### Apply

```bash
# Apply a saved plan
terraform apply "prod.tfplan"

# Apply with auto-approve (use only in CI/CD, not production)
terraform apply -var-file="terraform.tfvars" -auto-approve

# Apply targeting a specific resource
terraform apply -target="azurerm_linux_web_app.main" -var-file="terraform.tfvars"
```

### Destroy

```bash
# Always plan a destroy first
terraform plan -destroy -var-file="terraform.tfvars" -out="destroy.tfplan"

# Apply the destroy plan
terraform apply "destroy.tfplan"
```

> **Warning:** Destroying a production environment is irreversible. Ensure you have
> verified database backups before running destroy in production.

### Import Existing Resources

If Azure resources were created outside of Terraform (manually or by another tool),
import them into the state:

```bash
# Import a resource group
terraform import azurerm_resource_group.main \
  "/subscriptions/<sub-id>/resourceGroups/rg-auth-framework-prod"

# Import an App Service
terraform import module.app_service.azurerm_linux_web_app.main \
  "/subscriptions/<sub-id>/resourceGroups/rg-auth-framework-prod/providers/Microsoft.Web/sites/app-auth-framework-prod"

# Import a Key Vault
terraform import module.key_vault.azurerm_key_vault.main \
  "/subscriptions/<sub-id>/resourceGroups/rg-auth-framework-prod/providers/Microsoft.KeyVault/vaults/kv-auth-framework-prod"
```

### View Outputs

```bash
# All outputs
terraform output

# Specific output as raw string (no quotes — useful in scripts)
terraform output -raw acr_login_server

# Output as JSON
terraform output -json
```

### State Operations

```bash
# List all resources in state
terraform state list

# Show the state of a specific resource
terraform state show module.app_service.azurerm_linux_web_app.main

# Remove a resource from state without destroying it
terraform state rm azurerm_resource_group.main

# Move a resource within state (e.g., after a module rename)
terraform state mv \
  module.old_module.azurerm_linux_web_app.main \
  module.new_module.azurerm_linux_web_app.main
```

---

## Workspace Management

Terraform workspaces provide a lightweight way to manage multiple environments from a
single configuration directory. However, for this project, we use separate directories
per environment (`environments/dev`, `environments/staging`, `environments/prod`) with
shared modules. This approach provides:

- Complete isolation of state files
- Environment-specific variable files
- Different backend keys per environment
- Ability to have different module versions per environment

### If Using Workspaces (Alternative Approach)

```bash
# List workspaces
terraform workspace list

# Create a new workspace
terraform workspace new staging

# Select a workspace
terraform workspace select prod

# Show current workspace
terraform workspace show

# Use workspace name in resource naming
resource "azurerm_resource_group" "main" {
  name     = "rg-auth-framework-${terraform.workspace}"
  location = var.location
}
```

### Environment Promotion

To promote infrastructure changes from dev to staging to prod:

```bash
# 1. Apply and validate in dev
cd terraform/environments/dev
terraform apply -var-file="terraform.tfvars" -auto-approve

# 2. Run integration tests against dev

# 3. Apply to staging (with plan review)
cd terraform/environments/staging
terraform plan -var-file="terraform.tfvars" -out="staging.tfplan"
# Review plan output
terraform apply "staging.tfplan"

# 4. Validate staging environment

# 5. Apply to production (requires manual approval in CI/CD)
cd terraform/environments/prod
terraform plan -var-file="terraform.tfvars" -out="prod.tfplan"
# Peer review of plan output required
terraform apply "prod.tfplan"
```
