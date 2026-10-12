variable "name" {
  description = "Name prefix to be used on all resources as identifier"
  type        = string
  default     = "certara-vpc"
}

variable "vpc_cidr" {
  description = "The IPv4 CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_dns_hostnames" {
  description = "Should be true to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Should be true to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "availability_zones" {
  description = "List of 2 Availability Zones to deploy subnets in. If null, the first 2 available AZs in the region will be used."
  type        = list(string)
  default     = null
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the 2 public subnets (intended for Load Balancer / Reverse Proxy with direct internet access)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the 2 private subnets (intended for Application Servers with outbound internet access)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "Should be true to provision NAT Gateway(s) for private subnets outbound internet communication"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Should be true to use a single shared NAT Gateway across private subnets (cost-effective), or false for multi-AZ NAT Gateways (high availability)"
  type        = bool
  default     = true
}

variable "enable_s3_endpoint" {
  description = "Ensure calls to S3 API stay on AWS backbone network for security and cost reduction via Gateway VPC Endpoint"
  type        = bool
  default     = true
}

variable "tags" {
  description = "A map of tags to assign to all resources"
  type        = map(string)
  default     = {}
}
