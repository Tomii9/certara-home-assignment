variable "aws_region" {
  description = "The AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "localstack_endpoint" {
  description = "LocalStack endpoint URL for local testing"
  type        = string
  default     = "http://localhost:4566"
}

variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}
