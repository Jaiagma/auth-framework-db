# Auth Framework - Production Environment Variables
# Usage: terraform apply -var-file=examples/production-env.tfvars

environment   = "prod"
location      = "eastus2"
project_name  = "authframework"

# PostgreSQL - general purpose with HA
postgresql_sku_name   = "GP_Standard_D4s_v3"
postgresql_storage_mb = 65536
postgresql_version    = "16"

# App Service - premium tier for production
app_service_sku_name = "P2v3"

# Container Registry - standard (upgrade to premium for geo-replication)
acr_sku = "Standard"

# Key Vault - premium for HSM key operations
key_vault_sku_name = "premium"

# Enable HA for production
enable_high_availability = true

# Networking
vnet_address_space = "10.30.0.0/16"
app_subnet_prefix  = "10.30.1.0/24"
db_subnet_prefix   = "10.30.2.0/24"

# Monitoring
alert_email = "production-alerts@example.com"

tags = {
  Owner       = "platform-team"
  CostCenter  = "production"
  Application = "auth-framework"
  Criticality = "high"
  Compliance  = "required"
}
