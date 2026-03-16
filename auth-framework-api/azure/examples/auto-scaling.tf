# ============================================================
# Auto-Scaling Rules Example
# ============================================================

variable "as_resource_group" { default = "rg-authframework-prod" }
variable "as_plan_name"      { default = "authframework-prod-asp" }
variable "as_location"       { default = "eastus2" }

data "azurerm_service_plan" "target" {
  name                = var.as_plan_name
  resource_group_name = var.as_resource_group
}

resource "azurerm_monitor_autoscale_setting" "advanced" {
  name                = "authframework-prod-advanced-autoscale"
  resource_group_name = var.as_resource_group
  location            = var.as_location
  target_resource_id  = data.azurerm_service_plan.target.id

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 2
      maximum = 10
    }

    # Scale out: CPU > 70% for 5 minutes
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = data.azurerm_service_plan.target.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }

    # Scale in: CPU < 25% for 15 minutes
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = data.azurerm_service_plan.target.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 25
      }
      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M"
      }
    }

    # Scale out: Memory > 80% for 5 minutes
    rule {
      metric_trigger {
        metric_name        = "MemoryPercentage"
        metric_resource_id = data.azurerm_service_plan.target.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
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

  # Business hours: scale to min 3
  profile {
    name = "business-hours"

    capacity {
      default = 3
      minimum = 3
      maximum = 10
    }

    recurrence {
      timezone = "Eastern Standard Time"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [8]
      minutes  = [0]
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = data.azurerm_service_plan.target.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }
      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "2"
        cooldown  = "PT5M"
      }
    }
  }
}
