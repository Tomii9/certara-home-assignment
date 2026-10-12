module "vpc" {
  source = "../../modules/vpc"

  name                 = "certara-${var.environment}-vpc"
  vpc_cidr             = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 2 Public subnets for Load Balancer / Reverse Proxy (Direct internet access)
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # 2 Private subnets for Application Servers (Outbound internet via NAT Gateway)
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Ensure calls to S3 API stay on AWS private backbone network
  enable_s3_endpoint = true

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "Certara"
  }
}

# Traffic from within the VPC accesses this bucket privately via the S3 Gateway Endpoint.
resource "aws_s3_bucket" "application_storage" {
  bucket = "certara-${var.environment}-app-storage"

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "Private Application S3 Storage"
  }
}

# Security Groups demonstrating the subnet roles:
# 1. Public SG: For Load Balancers / Reverse Proxies (Inbound HTTP/HTTPS from Internet)
# 2. Private SG: For Application Servers (Inbound only from Load Balancers)
resource "aws_security_group" "load_balancer" {
  name        = "certara-${var.environment}-alb-sg"
  description = "Security group for Load Balancers in public subnets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
    from_port   = 444
    to_port     = 444
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "certara-${var.environment}-alb-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "application" {
  name        = "certara-${var.environment}-app-sg"
  description = "Security group for Application Servers in private subnets"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow traffic from load balancer only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  egress {
    description = "Allow outbound internet traffic via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "certara-${var.environment}-app-sg"
    Environment = var.environment
  }
}
