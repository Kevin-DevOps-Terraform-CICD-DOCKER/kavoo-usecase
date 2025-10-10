variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "services" {
  description = "List of service names for ECR repositories"
  type        = list(string)
  default     = [
    "front",
    "admins-api",
    "checkout-api", 
    "members-api",
    "users-api",
    "webhooks-api"
  ]
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    ecr_repositories = map(bool)
  })
}
