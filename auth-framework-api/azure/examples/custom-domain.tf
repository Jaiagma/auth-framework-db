# ============================================================
# Custom Domain and SSL Certificate Example
# ============================================================

variable "cd_app_name"       { default = "authframework-prod-api" }
variable "cd_resource_group" { default = "rg-authframework-prod" }
variable "cd_custom_domain"  { default = "api.yourdomain.com" }
variable "cd_certificate_password" {
  sensitive = true
  default   = ""
}

data "azurerm_linux_web_app" "target" {
  name                = var.cd_app_name
  resource_group_name = var.cd_resource_group
}

data "azurerm_resource_group" "target" {
  name = var.cd_resource_group
}

# App Service Managed Certificate (free, auto-renewed)
resource "azurerm_app_service_managed_certificate" "main" {
  custom_hostname_binding_id = azurerm_app_service_custom_hostname_binding.main.id
}

# Custom hostname binding
resource "azurerm_app_service_custom_hostname_binding" "main" {
  hostname            = var.cd_custom_domain
  app_service_name    = data.azurerm_linux_web_app.target.name
  resource_group_name = var.cd_resource_group
  # DNS CNAME must point to the app before this can be applied:
  # CNAME: api.yourdomain.com -> authframework-prod-api.azurewebsites.net
}

# Certificate binding (enforce HTTPS)
resource "azurerm_app_service_certificate_binding" "main" {
  hostname_binding_id = azurerm_app_service_custom_hostname_binding.main.id
  certificate_id      = azurerm_app_service_managed_certificate.main.id
  ssl_state           = "SniEnabled"
}

output "custom_domain_url" {
  value = "https://${var.cd_custom_domain}"
}
output "certificate_thumbprint" {
  value = azurerm_app_service_managed_certificate.main.thumbprint
}
