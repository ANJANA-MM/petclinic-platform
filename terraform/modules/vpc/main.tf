# All-public VPC: no NAT Gateway, no private subnets, no VPC endpoints.
# Security groups (security_groups.tf) are the access-control perimeter. See ADR-0001.

locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix

  # Mandatory tags last so callers cannot override them.
  common_tags = merge(
    var.tags,
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    },
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-vpc"
    Component = "networking"
  })
}

# Strip all rules from the default SG so nothing launched without an explicit SG
# inherits allow-all-within-group behaviour.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-default-sg-do-not-use"
    Component = "security"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-igw"
    Component = "networking"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true # checkov:skip=CKV_AWS_130:All-public design, see ADR-0001

  lifecycle {
    precondition {
      condition     = length(var.public_subnet_cidrs) == length(var.availability_zones)
      error_message = "public_subnet_cidrs and availability_zones must have the same length."
    }
  }

  tags = merge(local.common_tags, {
    Name                                          = "${local.name_prefix}-public-${substr(var.availability_zones[count.index], -1, 1)}"
    Component                                     = "networking"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, {
    Name      = "${local.name_prefix}-public-rt"
    Component = "networking"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
