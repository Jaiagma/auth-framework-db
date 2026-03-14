resource "azurerm_service_plan" "main" {
  name                = "${local.resource_prefix}-asp"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = var.app_service_sku_name
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "main" {
  name                = "${local.resource_prefix}-api"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on         = true
    health_check_path = "/health"

    application_stack {
      docker_image_name   = "${azurerm_container_registry.main.login_server}/authframework-api:latest"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }

    ip_restriction_default_action = "Allow"

    cors {
      allowed_origins     = ["https://${local.resource_prefix}-api.azurewebsites.net"]
      support_credentials = false
    }
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = var.environment == "prod" ? "Production" : title(var.environment)
    ASPNETCORE_URLS        = "http://+:8080"
    WEBSITES_PORT          = "8080"

    "ConnectionStrings__DefaultConnection" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=db-connection-string)"

    "JwtSettings__SecretKey"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=jwt-secret-key)"
    "JwtSettings__Issuer"          = "https://${local.resource_prefix}-api.azurewebsites.net"
    "JwtSettings__Audience"        = "authframework-api"
    "JwtSettings__ExpiryMinutes"   = var.environment == "prod" ? "30" : "60"
    "JwtSettings__RefreshExpiryDays" = "7"

    "EncryptionSettings__Key" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=encryption-key)"

    APPLICATIONINSIGHTS_CONNECTION_STRING = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=appinsights-connection-string)"
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"

    DOCKER_REGISTRY_SERVER_URL      = "https://${azurerm_container_registry.main.login_server}"
    DOCKER_ENABLE_CI                = "true"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"
  }

  logs {
    http_logs {
      retention_in_days = 7
    }
    application_logs {
      file_system_level = "Warning"
    }
  }

  virtual_network_subnet_id = azurerm_subnet.app.id

  tags = local.common_tags

  depends_on = [
    azurerm_key_vault_secret.db_connection_string,
    azurerm_key_vault_secret.jwt_secret_key,
    azurerm_key_vault_secret.encryption_key,
  ]
}

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.main.id
  https_only     = true

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on         = false
    health_check_path = "/health"

    application_stack {
      docker_image_name   = "${azurerm_container_registry.main.login_server}/authframework-api:latest"
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    ASPNETCORE_ENVIRONMENT = "Staging"
    ASPNETCORE_URLS        = "http://+:8080"
    WEBSITES_PORT          = "8080"

    "ConnectionStrings__DefaultConnection" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=db-connection-string)"

    "JwtSettings__SecretKey"       = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=jwt-secret-key)"
    "JwtSettings__Issuer"          = "https://${local.resource_prefix}-api-staging.azurewebsites.net"
    "JwtSettings__Audience"        = "authframework-api"
    "JwtSettings__ExpiryMinutes"   = "60"

    "EncryptionSettings__Key" = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=encryption-key)"

    APPLICATIONINSIGHTS_CONNECTION_STRING = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=appinsights-connection-string)"

    DOCKER_REGISTRY_SERVER_URL = "https://${azurerm_container_registry.main.login_server}"
  }

  tags = local.common_tags
}

resource "azurerm_monitor_autoscale_setting" "main" {
  name                = "${local.resource_prefix}-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_service_plan.main.id
  tags                = local.common_tags

  profile {
    name = "defaultProfile"

    capacity {
      default = 1
      minimum = 1
      maximum = 5
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }
}
