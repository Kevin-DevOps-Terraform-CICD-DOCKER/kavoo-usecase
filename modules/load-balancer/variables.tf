variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group ID"
  type        = string
}

variable "api_services" {
  description = "List of API service names"
  type        = list(string)
  default     = [
    "admins-api",
    "checkout-api", 
    "members-api",
    "users-api",
    "webhooks-api"
  ]
}

variable "certificate_arn" {
  description = "SSL certificate ARN (optional)"
  type        = string
  default     = ""
}

variable "domain_name" {
  description = "Domain name for the application (optional)"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Route 53 hosted zone ID (optional)"
  type        = string
  default     = ""
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the load balancer"
  type        = bool
  default     = true
}

variable "service_ports" {
  description = "Map of service ports"
  type        = map(number)
  default     = {
    front        = 3000
    admins-api   = 8080
    checkout-api = 8081
    members-api  = 8082
    users-api    = 8083
    webhooks-api = 8084
  }
}

variable "services" {
  description = "Map of service configurations"
  type = map(object({
    cpu          = number
    memory       = number
    port         = number
    health_path  = string
    min_capacity = number
    max_capacity = number
    priority     = number
  }))
  default = {}
}

variable "create_load_balancer" {
  description = "Whether to create the load balancer"
  type        = bool
  default     = true
}

variable "create_target_groups" {
  description = "Whether to create target groups"
  type        = bool
  default     = true
}

variable "create_listener_rules" {
  description = "Whether to create listener rules"
  type        = bool
  default     = true
}

variable "existing_listener_arn" {
  description = "ARN of existing listener to use for rules (when not creating new ones)"
  type        = string
  default     = ""
}

variable "create_listeners" {
  description = "Whether to create listeners (HTTP/HTTPS)"
  type        = bool
  default     = true
}
