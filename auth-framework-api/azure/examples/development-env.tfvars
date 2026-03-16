# Auth Framework - Development Environment Variables
# Usage: terraform apply -var-file=examples/development-env.tfvars

environment   = "dev"
location      = "eastus2"
project_name  = "authframework"

# PostgreSQL - smallest burstable SKU for dev
postgresql_sku_name   = "B_Standard_B1ms"
postgresql_storage_mb = 32768
postgresql_version    = "16"

# App Service - basic tier for dev
app_service_sku_name = "B1"

# Container Registry - basic tier for dev
acr_sku = "Basic"

# Key Vault
key_vault_sku_name = "standard"

# No HA for dev
enable_high_availability = false

# Networking
vnet_address_space = "10.10.0.0/16"
app_subnet_prefix  = "10.10.1.0/24"
db_subnet_prefix   = "10.10.2.0/24"

# Monitoring
alert_email = "dev-team@example.com"

tags = {
  Owner        = "dev-team"
  CostCenter   = "development"
  Application  = "auth-framework"
  AutoShutdown = "true"
}
