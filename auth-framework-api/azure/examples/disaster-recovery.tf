# ============================================================
# Disaster Recovery Configuration
# Geo-redundant backups + secondary region App Service
# ============================================================

variable "dr_project_name"        { default = "authframework" }
variable "dr_environment"         { default = "prod" }
variable "dr_primary_location"    { default = "eastus2" }
variable "dr_secondary_location"  { default = "westus2" }
variable "dr_db_password" {
  sensitive = true
  default   = null
}

locals {
  dr_prefix = "${var.dr_project_name}-${var.dr_environment}"
}

resource "azurerm_resource_group" "dr_primary" {
  name     = "rg-${local.dr_prefix}-primary"
  location = var.dr_primary_location
}

resource "azurerm_resource_group" "dr_secondary" {
  name     = "rg-${local.dr_prefix}-secondary"
  location = var.dr_secondary_location
}

# Primary PostgreSQL with geo-redundant backup
resource "azurerm_postgresql_flexible_server" "dr_primary" {
  name                   = "${local.dr_prefix}-primary-psql"
  resource_group_name    = azurerm_resource_group.dr_primary.name
  location               = azurerm_resource_group.dr_primary.location
  version                = "16"
  administrator_login    = "psqladmin"
  administrator_password = var.dr_db_password
  zone                   = "1"
  sku_name               = "GP_Standard_D2s_v3"
  storage_mb             = 65536

  backup_retention_days        = 35
  geo_redundant_backup_enabled = true

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }
}

# Secondary App Service (warm standby)
resource "azurerm_service_plan" "dr_secondary" {
  name                = "${local.dr_prefix}-secondary-asp"
  resource_group_name = azurerm_resource_group.dr_secondary.name
  location            = azurerm_resource_group.dr_secondary.location
  os_type             = "Linux"
  sku_name            = "B2"
}

# Storage account for backup storage
resource "azurerm_storage_account" "dr_backups" {
  name                     = replace("${local.dr_prefix}drbackups", "-", "")
  resource_group_name      = azurerm_resource_group.dr_primary.name
  location                 = var.dr_secondary_location
  account_tier             = "Standard"
  account_replication_type = "GRS"
  min_tls_version          = "TLS1_2"
}

resource "azurerm_storage_container" "db_backups" {
  name                  = "db-backups"
  storage_account_name  = azurerm_storage_account.dr_backups.name
  container_access_type = "private"
}

output "dr_backup_storage_account" {
  value = azurerm_storage_account.dr_backups.name
}
