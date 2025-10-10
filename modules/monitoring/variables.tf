variable "project_name" {
  description = "Project name"
  type        = string
  
  validation {
    condition     = length(var.project_name) > 0 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only alphanumeric characters and hyphens."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "600"
  
  validation {
    condition     = can(tonumber(var.monthly_budget_limit)) && tonumber(var.monthly_budget_limit) > 0
    error_message = "Monthly budget limit must be a positive number."
  }
}

variable "budget_alert_threshold_1" {
  description = "First budget alert threshold (percentage)"
  type        = number
  default     = 80
  
  validation {
    condition     = var.budget_alert_threshold_1 > 0 && var.budget_alert_threshold_1 <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "budget_alert_threshold_2" {
  description = "Second budget alert threshold (percentage)"
  type        = number
  default     = 95
  
  validation {
    condition     = var.budget_alert_threshold_2 > 0 && var.budget_alert_threshold_2 <= 100
    error_message = "Budget alert threshold must be between 1 and 100."
  }
}

variable "alert_email_addresses" {
  description = "List of email addresses for budget alerts"
  type        = list(string)
  default     = ["admin@kavoo.com"]
  
  validation {
    condition = length(var.alert_email_addresses) > 0 && alltrue([
      for email in var.alert_email_addresses : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))
    ])
    error_message = "All email addresses must be valid and at least one email must be provided."
  }
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    budget_exists    = bool
    dashboard_exists = bool
    alarm_exists     = bool
  })
  default = {
    budget_exists    = false
    dashboard_exists = false
    alarm_exists     = false
  }
}

variable "budget_limit" {
  description = "Budget limit in USD"
  type        = number
  default     = 100
}

variable "notification_email" {
  description = "Email for budget notifications"
  type        = string
  default     = ""
}