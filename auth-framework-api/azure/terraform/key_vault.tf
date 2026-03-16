resource "random_password" "jwt_secret" {
  count   = var.jwt_secret_key == null ? 1 : 0
  length  = 64
  special = false
}

resource "random_password" "encryption_key" {
  count   = var.encryption_key == null ? 1 : 0
  length  = 32
  special = false
}

locals {
  jwt_secret_value     = var.jwt_secret_key != null ? var.jwt_secret_key : random_password.jwt_secret[0].result
  encryption_key_value = var.encryption_key != null ? var.encryption_key : random_password.encryption_key[0].result
  db_connection_string = "Host=${azurerm_postgresql_flexible_server.main.fqdn};Port=5432;Database=authframework;Username=${var.postgresql_admin_username};Password=${local.db_password_value};SslMode=VerifyFull"
}

resource "azurerm_key_vault" "main" {
  name                       = "${local.resource_prefix}-kv"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku_name
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  network_acls {
    default_action             = "Allow"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.app.id]
  }

  tags = local.common_tags
}

resource "azurerm_key_vault_access_policy" "terraform_deployer" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Purge", "Recover", "Backup", "Restore"
  ]

  key_permissions = [
    "Get", "List", "Create", "Delete", "Update", "Import", "Backup", "Restore", "Recover", "Purge"
  ]
}

resource "azurerm_key_vault_access_policy" "app_service" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app.main.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_access_policy" "staging_slot" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_linux_web_app_slot.staging.identity[0].principal_id

  secret_permissions = ["Get", "List"]
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = local.db_password_value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform_deployer]
}

resource "azurerm_key_vault_secret" "db_connection_string" {
  name         = "db-connection-string"
  value        = local.db_connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.terraform_deployer,
    azurerm_postgresql_flexible_server.main
  ]
}

resource "azurerm_key_vault_secret" "jwt_secret_key" {
  name         = "jwt-secret-key"
  value        = local.jwt_secret_value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform_deployer]
}

resource "azurerm_key_vault_secret" "encryption_key" {
  name         = "encryption-key"
  value        = local.encryption_key_value
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [azurerm_key_vault_access_policy.terraform_deployer]
}

resource "azurerm_key_vault_secret" "appinsights_connection_string" {
  name         = "appinsights-connection-string"
  value        = azurerm_application_insights.main.connection_string
  key_vault_id = azurerm_key_vault.main.id
  tags         = local.common_tags

  depends_on = [
    azurerm_key_vault_access_policy.terraform_deployer,
    azurerm_application_insights.main
  ]
}
