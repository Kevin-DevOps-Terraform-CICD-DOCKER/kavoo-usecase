resource "aws_vpc" "main" {
  count = var.existing_resources.vpc_exists ? 0 : 1

  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

data "aws_lb" "existing_alb" {
  count = var.existing_resources.vpc_exists && var.existing_resources.existing_vpc_id == null ? 1 : 0
  name  = "${var.project_name}-alb"
}

data "aws_security_groups" "project_sgs" {
  count = var.existing_resources.vpc_exists && var.existing_resources.existing_vpc_id == null ? 1 : 0
  
  filter {
    name   = "group-name"
    values = ["${var.project_name}-*"]
  }
  
  lifecycle {
    postcondition {
      condition     = length(self.ids) > 0 || length(data.aws_lb.existing_alb) > 0
      error_message = "Não foi possível descobrir VPC automaticamente. Forneça existing_vpc_id ou certifique-se que ALB '${var.project_name}-alb' existe."
    }
  }
}

data "aws_vpc" "existing" {
  count = var.existing_resources.vpc_exists ? 1 : 0
  
  id = local.discovered_vpc_id
}

data "aws_security_group" "project_sg_details" {
  count = (var.existing_resources.vpc_exists && 
           var.existing_resources.existing_vpc_id == null && 
           length(data.aws_security_groups.project_sgs) > 0 && 
           length(flatten([for sg in data.aws_security_groups.project_sgs : sg.ids])) > 0) ? 1 : 0
           
  id = length(data.aws_security_groups.project_sgs) > 0 ? (
    length(data.aws_security_groups.project_sgs[0].ids) > 0 ? 
    data.aws_security_groups.project_sgs[0].ids[0] : null
  ) : null
}

data "aws_subnets" "existing_public" {
  count = var.existing_resources.vpc_exists ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnets" "existing_private" {
  count = var.existing_resources.vpc_exists ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnets" "all_existing" {
  count = var.existing_resources.vpc_exists ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing[0].id]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnet" "existing_subnet_details" {
  for_each = var.existing_resources.vpc_exists ? toset(data.aws_subnets.all_existing[0].ids) : toset([])
  id       = each.value
}

locals {
  discovered_vpc_id = var.existing_resources.existing_vpc_id != null ? var.existing_resources.existing_vpc_id : (
    length(data.aws_lb.existing_alb) > 0 ? data.aws_lb.existing_alb[0].vpc_id : (
      length(data.aws_security_group.project_sg_details) > 0 ? 
      data.aws_security_group.project_sg_details[0].vpc_id : null
    )
  )
}

locals {
  vpc_id = var.existing_resources.vpc_exists ? local.discovered_vpc_id : aws_vpc.main[0].id

  alb_security_group_id      = var.create_security_groups.alb ? aws_security_group.alb[0].id : data.aws_security_group.existing_alb[0].id
  ecs_security_group_id      = var.create_security_groups.ecs ? aws_security_group.ecs[0].id : data.aws_security_group.existing_ecs[0].id
  database_security_group_id = var.create_security_groups.database ? aws_security_group.database[0].id : data.aws_security_group.existing_database[0].id
  redis_security_group_id    = var.create_security_groups.redis ? aws_security_group.redis[0].id : data.aws_security_group.existing_redis[0].id

  available_security_groups = (!var.create_security_groups.alb || !var.create_security_groups.ecs || !var.create_security_groups.database || !var.create_security_groups.redis) ? data.aws_security_groups.existing_sg_list[0].ids : []

  available_subnets = var.existing_resources.vpc_exists ? data.aws_subnets.all_existing[0].ids : []

  real_existing_subnets = var.existing_resources.vpc_exists ? [
    for subnet_id in local.available_subnets : subnet_id
    if subnet_id != null && subnet_id != "" && can(regex("^subnet-[a-z0-9]+$", subnet_id))
  ] : []

  desired_az_existing_subnets = var.existing_resources.vpc_exists ? [
    for s in values(data.aws_subnet.existing_subnet_details) : s.id
    if contains(var.availability_zones, s.availability_zone)
  ] : []

  private_subnet_ids = var.existing_resources.vpc_exists ? (
    length(local.desired_az_existing_subnets) >= 2 ? slice(local.desired_az_existing_subnets, 0, 2) : (
      length(local.real_existing_subnets) >= 2 ? slice(local.real_existing_subnets, 0, 2) : aws_subnet.private[*].id
    )
  ) : aws_subnet.private[*].id

  public_subnet_ids = var.existing_resources.vpc_exists ? (
    length(local.desired_az_existing_subnets) >= 2 ? slice(local.desired_az_existing_subnets, 0, 2) : (
      length(local.real_existing_subnets) >= 2 ? slice(local.real_existing_subnets, 0, 2) : aws_subnet.public[*].id
    )
  ) : aws_subnet.public[*].id
}

resource "null_resource" "subnet_validation" {
  count = var.existing_resources.vpc_exists && length(local.real_existing_subnets) == 0 ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: VPC ${var.existing_resources.existing_vpc_id} exists but has no subnets. This should have been caught in the workflow.' && exit 1"
  }
}

resource "aws_internet_gateway" "main" {
  count  = var.existing_resources.vpc_exists ? 0 : 1
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name        = "kavoo-igw"
    Environment = var.environment
    Project     = "kavoo"
  }
}

resource "aws_subnet" "public" {
  count = var.existing_resources.vpc_exists ? (
    length(local.real_existing_subnets) < 2 ? length(var.availability_zones) : 0
  ) : length(var.availability_zones)

  vpc_id = local.vpc_id
  cidr_block = var.existing_resources.vpc_exists && length(local.real_existing_subnets) > 0 ? "10.0.${20 + count.index}.0/24" : var.public_subnet_cidrs[count.index]
  availability_zone       = count.index == 0 ? "us-east-1b" : (count.index == 1 ? "us-east-1a" : var.availability_zones[count.index])
  map_public_ip_on_launch = true

  tags = {
    Name        = "kavoo-public-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "kavoo"
    Type        = "Public"
  }
}

resource "aws_subnet" "private" {
  count = var.existing_resources.vpc_exists ? (
    length(local.real_existing_subnets) < 2 ? length(var.availability_zones) : 0
  ) : length(var.availability_zones)

  vpc_id = local.vpc_id
  cidr_block = var.existing_resources.vpc_exists && length(local.real_existing_subnets) > 0 ? "10.0.${30 + count.index}.0/24" : var.private_subnet_cidrs[count.index]
  availability_zone = count.index == 0 ? "us-east-1b" : (count.index == 1 ? "us-east-1a" : var.availability_zones[count.index])

  tags = {
    Name        = "kavoo-private-subnet-${count.index + 1}"
    Environment = var.environment
    Project     = "kavoo"
    Type        = "Private"
  }
}

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? length(aws_subnet.public) : 0

  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${var.project_name}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "main" {
  count = var.enable_nat_gateway ? length(aws_subnet.public) : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  count  = var.existing_resources.vpc_exists ? 0 : length(var.availability_zones)
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name        = "kavoo-public-rt-${count.index + 1}"
    Environment = var.environment
    Project     = "kavoo"
  }
}

resource "aws_route_table" "private" {
  count  = var.existing_resources.vpc_exists ? 0 : length(var.availability_zones)
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name        = "kavoo-private-rt-${count.index + 1}"
    Environment = var.environment
    Project     = "kavoo"
  }
}

resource "aws_route_table_association" "public" {
  count          = var.existing_resources.vpc_exists ? 0 : length(var.availability_zones)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = var.existing_resources.vpc_exists ? 0 : length(var.availability_zones)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

data "aws_security_groups" "existing_sg_list" {
  count = (!var.create_security_groups.alb || !var.create_security_groups.ecs || !var.create_security_groups.database || !var.create_security_groups.redis) ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
}

data "aws_security_group" "default" {
  count = (!var.create_security_groups.alb || !var.create_security_groups.ecs || !var.create_security_groups.database || !var.create_security_groups.redis) ? 1 : 0
  
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }
  
  filter {
    name   = "group-name"
    values = ["default"]
  }
}

data "aws_security_group" "existing_alb" {
  count = var.create_security_groups.alb ? 0 : 1

  id = data.aws_security_group.default[0].id
}

data "aws_security_group" "existing_ecs" {
  count = var.create_security_groups.ecs ? 0 : 1

  id = data.aws_security_group.default[0].id
}

data "aws_security_group" "existing_database" {
  count = var.create_security_groups.database ? 0 : 1

  id = data.aws_security_group.default[0].id
}

data "aws_security_group" "existing_redis" {
  count = var.create_security_groups.redis ? 0 : 1

  id = data.aws_security_group.default[0].id
}

resource "aws_security_group" "alb" {
  count       = var.create_security_groups.alb ? 1 : 0
  name        = "${var.project_name}-alb-sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs" {
  count       = var.create_security_groups.ecs ? 1 : 0
  name        = "${var.project_name}-ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ecs-sg"
  }
}

resource "aws_security_group" "database" {
  count       = var.create_security_groups.database ? 1 : 0
  name        = "${var.project_name}-database-sg"
  description = "Security group for database"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-database-sg"
  }
}

resource "aws_security_group" "redis" {
  count       = var.create_security_groups.redis ? 1 : 0
  name        = "${var.project_name}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = local.vpc_id

  tags = {
    Name = "${var.project_name}-redis-sg"
  }
}

resource "aws_security_group_rule" "ecs_from_alb" {
  count                    = var.create_security_groups.ecs ? 1 : 0
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = local.alb_security_group_id
  security_group_id        = aws_security_group.ecs[0].id
  description              = "Allow traffic from ALB"
}

resource "aws_security_group_rule" "database_from_ecs" {
  count                    = var.create_security_groups.database ? 1 : 0
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = local.ecs_security_group_id
  security_group_id        = aws_security_group.database[0].id
  description              = "Allow PostgreSQL from ECS"
}

resource "aws_security_group_rule" "redis_from_ecs" {
  count                    = var.create_security_groups.redis ? 1 : 0
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = local.ecs_security_group_id
  security_group_id        = aws_security_group.redis[0].id
  description              = "Allow Redis from ECS"
}

resource "aws_route" "private_nat_gateway" {
  count = var.existing_resources.vpc_exists ? 0 : (var.enable_nat_gateway ? length(var.availability_zones) : 0)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[count.index].id
}