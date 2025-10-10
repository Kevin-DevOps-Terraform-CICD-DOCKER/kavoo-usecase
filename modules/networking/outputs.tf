output "vpc_id" {
  description = "ID of the VPC"
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = var.existing_resources.vpc_exists ? data.aws_vpc.existing[0].cidr_block : aws_vpc.main[0].cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = local.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"  
  value       = local.private_subnet_ids
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = var.existing_resources.vpc_exists ? null : (length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null)
}

output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = local.alb_security_group_id
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = local.ecs_security_group_id
}

output "database_security_group_id" {
  description = "ID of the database security group"
  value       = local.database_security_group_id
}

output "redis_security_group_id" {
  description = "ID of the Redis security group"
  value       = local.redis_security_group_id
}

output "public_route_table_ids" {
  description = "IDs of the public route tables"
  value       = var.existing_resources.vpc_exists ? [] : aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "IDs of the private route tables"
  value       = var.existing_resources.vpc_exists ? [] : aws_route_table.private[*].id
}

output "security_group_alb_id" {
  description = "ID of the ALB security group"
  value       = local.alb_security_group_id
}

output "security_group_ecs_id" {
  description = "ID of the ECS security group"
  value       = local.ecs_security_group_id
}

output "security_group_database_id" {
  description = "ID of the database security group"
  value       = local.database_security_group_id
}

output "security_group_redis_id" {
  description = "ID of the Redis security group"
  value       = local.redis_security_group_id
}

output "debug_security_groups" {
  description = "Debug information about available security groups"
  value = {
    available_security_groups = local.available_security_groups
    using_existing            = !var.create_security_groups.alb
    vpc_id                   = local.vpc_id
  }
}

output "vpc_discovery_info" {
  description = "Information about how VPC was discovered dynamically"
  value = {
    vpc_id_provided           = var.existing_resources.existing_vpc_id
    vpc_id_from_alb          = length(data.aws_lb.existing_alb) > 0 ? data.aws_lb.existing_alb[0].vpc_id : null
    vpc_id_from_security_groups = length(data.aws_security_group.project_sg_details) > 0 ? data.aws_security_group.project_sg_details[0].vpc_id : null
    final_vpc_id             = local.discovered_vpc_id
    discovery_method         = var.existing_resources.existing_vpc_id != null ? "provided" : (
      length(data.aws_lb.existing_alb) > 0 ? "alb" : (
        length(data.aws_security_group.project_sg_details) > 0 ? "security_group" : "not_found"
      )
    )
  }
}