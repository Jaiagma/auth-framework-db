# ============================================================
# Multi-Region Setup with Azure Traffic Manager
# Example: East US 2 (primary) + West US 2 (secondary)
# ============================================================

variable "primary_location" {
  default = "eastus2"
}
variable "secondary_location" {
  default = "westus2"
}
variable "project_name" {
  default = "authframework"
}
variable "environment" {
  default = "prod"
}

locals {
  primary_prefix   = "${var.project_name}-${var.environment}-primary"
  secondary_prefix = "${var.project_name}-${var.environment}-secondary"
}

# Primary resource group
resource "azurerm_resource_group" "primary" {
  name     = "rg-${var.project_name}-${var.environment}-primary"
  location = var.primary_location
  tags     = { Region = "primary", Environment = var.environment }
}

# Secondary resource group
resource "azurerm_resource_group" "secondary" {
  name     = "rg-${var.project_name}-${var.environment}-secondary"
  location = var.secondary_location
  tags     = { Region = "secondary", Environment = var.environment }
}

# Primary App Service Plan
resource "azurerm_service_plan" "primary" {
  name                = "${local.primary_prefix}-asp"
  resource_group_name = azurerm_resource_group.primary.name
  location            = azurerm_resource_group.primary.location
  os_type             = "Linux"
  sku_name            = "P1v3"
  tags                = { Region = "primary" }
}

# Secondary App Service Plan
resource "azurerm_service_plan" "secondary" {
  name                = "${local.secondary_prefix}-asp"
  resource_group_name = azurerm_resource_group.secondary.name
  location            = azurerm_resource_group.secondary.location
  os_type             = "Linux"
  sku_name            = "P1v3"
  tags                = { Region = "secondary" }
}

# Traffic Manager Profile
resource "azurerm_traffic_manager_profile" "main" {
  name                = "${var.project_name}-${var.environment}-tm"
  resource_group_name = azurerm_resource_group.primary.name

  traffic_routing_method = "Performance"

  dns_config {
    relative_name = "${var.project_name}-${var.environment}"
    ttl           = 60
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = { Environment = var.environment }
}

# Traffic Manager Endpoint - Primary
resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name                 = "primary-endpoint"
  profile_id           = azurerm_traffic_manager_profile.main.id
  always_serve_enabled = true
  priority             = 1
  target_resource_id   = azurerm_service_plan.primary.id
}

# Traffic Manager Endpoint - Secondary
resource "azurerm_traffic_manager_azure_endpoint" "secondary" {
  name                 = "secondary-endpoint"
  profile_id           = azurerm_traffic_manager_profile.main.id
  always_serve_enabled = false
  priority             = 2
  target_resource_id   = azurerm_service_plan.secondary.id
}

output "traffic_manager_fqdn" {
  value = azurerm_traffic_manager_profile.main.fqdn
}
