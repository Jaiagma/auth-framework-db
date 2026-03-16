# ============================================================
# High Availability Configuration
# Zone-redundant PostgreSQL + P-tier App Service
# ============================================================

variable "ha_environment"  { default = "prod" }
variable "ha_project_name" { default = "authframework" }
variable "ha_location"     { default = "eastus2" }
variable "ha_db_password" {
  sensitive = true
  default   = null
}

locals {
  ha_prefix = "${var.ha_project_name}-${var.ha_environment}"
}

resource "azurerm_resource_group" "ha" {
  name     = "rg-${local.ha_prefix}-ha"
  location = var.ha_location
}

# Zone-Redundant PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "ha" {
  name                   = "${local.ha_prefix}-ha-psql"
  resource_group_name    = azurerm_resource_group.ha.name
  location               = azurerm_resource_group.ha.location
  version                = "16"
  administrator_login    = "psqladmin"
  administrator_password = var.ha_db_password
  zone                   = "1"
  sku_name               = "GP_Standard_D4s_v3"
  storage_mb             = 65536

  backup_retention_days        = 35
  geo_redundant_backup_enabled = true

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 2
    start_minute = 0
  }
}

# Premium App Service Plan (zone-redundant capable)
resource "azurerm_service_plan" "ha" {
  name                   = "${local.ha_prefix}-ha-asp"
  resource_group_name    = azurerm_resource_group.ha.name
  location               = azurerm_resource_group.ha.location
  os_type                = "Linux"
  sku_name               = "P2v3"
  zone_balancing_enabled = true
}

output "ha_postgresql_fqdn" {
  value = azurerm_postgresql_flexible_server.ha.fqdn
}
