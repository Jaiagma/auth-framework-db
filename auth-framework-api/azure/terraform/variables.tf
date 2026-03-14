variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus2"
}

variable "project_name" {
  description = "Project name used as prefix for all resources"
  type        = string
  default     = "authframework"

  validation {
    condition     = can(regex("^[a-z0-9]{3,20}$", var.project_name))
    error_message = "Project name must be 3-20 lowercase alphanumeric characters."
  }
}

variable "postgresql_sku_name" {
  description = "PostgreSQL Flexible Server SKU name"
  type        = string
  default     = "GP_Standard_D2s_v3"
}

variable "postgresql_storage_mb" {
  description = "PostgreSQL storage in megabytes"
  type        = number
  default     = 32768

  validation {
    condition     = contains([32768, 65536, 131072, 262144, 524288, 1048576], var.postgresql_storage_mb)
    error_message = "Storage must be one of the supported sizes (32768, 65536, 131072, 262144, 524288, 1048576 MB)."
  }
}

variable "postgresql_version" {
  description = "PostgreSQL major version"
  type        = string
  default     = "16"
}

variable "postgresql_admin_username" {
  description = "PostgreSQL administrator username"
  type        = string
  default     = "psqladmin"
}

variable "app_service_sku_name" {
  description = "Azure App Service Plan SKU name"
  type        = string
  default     = "B2"
}

variable "acr_sku" {
  description = "Azure Container Registry SKU (Basic, Standard, Premium)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "ACR SKU must be Basic, Standard, or Premium."
  }
}

variable "key_vault_sku_name" {
  description = "Azure Key Vault SKU (standard or premium)"
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku_name)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "alert_email" {
  description = "Email address for monitoring alerts"
  type        = string
  default     = "ops@example.com"
}

variable "db_password" {
  description = "PostgreSQL administrator password"
  type        = string
  sensitive   = true
  default     = null
}

variable "jwt_secret_key" {
  description = "JWT signing secret key (minimum 32 characters)"
  type        = string
  sensitive   = true
  default     = null
}

variable "encryption_key" {
  description = "Data encryption key (exactly 32 characters)"
  type        = string
  sensitive   = true
  default     = null
}

variable "enable_high_availability" {
  description = "Enable zone-redundant high availability for PostgreSQL"
  type        = bool
  default     = false
}

variable "vnet_address_space" {
  description = "Virtual network address space"
  type        = string
  default     = "10.0.0.0/16"
}

variable "app_subnet_prefix" {
  description = "App Service subnet address prefix"
  type        = string
  default     = "10.0.1.0/24"
}

variable "db_subnet_prefix" {
  description = "Database subnet address prefix"
  type        = string
  default     = "10.0.2.0/24"
}
