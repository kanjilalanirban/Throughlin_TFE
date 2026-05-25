variable "name_prefix" {
  description = "Prefix for resource names (e.g. \"companybrain-phase0\")."
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "availability_zones" {
  description = "Two AZs to span. The compute is single-AZ in Phase 0; the second subnet exists only because RDS requires a subnet group across two AZs."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones are required for the RDS subnet group."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (host ALB and NAT GW)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets (host Fargate, Lambda, RDS)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]
}
