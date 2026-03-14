# Auth Framework - Staging Environment Variables
# Usage: terraform apply -var-file=examples/staging-env.tfvars

environment   = "staging"
location      = "eastus2"
project_name  = "authframework"

# PostgreSQL - general purpose for staging
postgresql_sku_name   = "GP_Standard_D2s_v3"
postgresql_storage_mb = 32768
postgresql_version    = "16"

# App Service - standard tier for staging
app_service_sku_name = "B2"

# Container Registry - standard tier
acr_sku = "Standard"

# Key Vault
key_vault_sku_name = "standard"

# No HA for staging (save cost)
enable_high_availability = false

# Networking
vnet_address_space = "10.20.0.0/16"
app_subnet_prefix  = "10.20.1.0/24"
db_subnet_prefix   = "10.20.2.0/24"

# Monitoring
alert_email = "staging-alerts@example.com"

tags = {
  Owner       = "platform-team"
  CostCenter  = "staging"
  Application = "auth-framework"
}
