variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1b", "us-east-1a"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets"
  type        = bool
  default     = true
}

variable "existing_resources" {
  description = "Configuration for existing AWS resources"
  type = object({
    vpc_exists      = bool
    existing_vpc_id = string
  })
  default = {
    vpc_exists      = false
    existing_vpc_id = null
  }
}

variable "create_security_groups" {
  description = "Whether to create new security groups or use existing ones"
  type = object({
    alb      = bool
    ecs      = bool
    database = bool
    redis    = bool
  })
  default = {
    alb      = true
    ecs      = true
    database = true
    redis    = true
  }
}