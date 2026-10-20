variable "project" {
  description = "Project name, used in resource naming and tags"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Environment name (dev or prod)"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24
    error_message = "vpc_cidr must be an IPv4 CIDR with a prefix length between /16 and /24."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per availability zone"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones for the public subnets, same order as public_subnet_cidrs"
  type        = list(string)

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required (EKS and RDS need multi-AZ subnets)."
  }
}

variable "enable_flow_logs" {
  description = "Create VPC flow logs delivered to CloudWatch Logs"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "CloudWatch retention (days) for VPC flow logs"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags merged onto every resource"
  type        = map(string)
  default     = {}
}
