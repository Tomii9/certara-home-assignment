output "vpc_id" {
  description = "The ID of the deployed VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "availability_zones" {
  description = "The availability zones used across subnets"
  value       = module.vpc.availability_zones
}

output "public_subnet_ids" {
  description = "Public subnet IDs (for Load Balancer / Reverse Proxy)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for Application Servers)"
  value       = module.vpc.private_subnet_ids
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "The ID(s) of the NAT Gateway(s)"
  value       = module.vpc.nat_gateway_ids
}

output "nat_public_ips" {
  description = "Elastic IP(s) of the NAT Gateway(s)"
  value       = module.vpc.nat_public_ips
}

output "s3_vpc_endpoint_id" {
  description = "The ID of the S3 VPC Gateway Endpoint (keeps S3 traffic on AWS backbone)"
  value       = module.vpc.s3_vpc_endpoint_id
}

output "s3_vpc_endpoint_prefix_list_id" {
  description = "Prefix list ID of the S3 VPC Endpoint"
  value       = module.vpc.s3_vpc_endpoint_prefix_list_id
}

output "s3_bucket_name" {
  description = "Example S3 bucket name accessible via private VPC endpoint"
  value       = aws_s3_bucket.application_storage.bucket
}

output "load_balancer_security_group_id" {
  description = "Security group ID for Load Balancers in public subnets"
  value       = aws_security_group.load_balancer.id
}

output "application_security_group_id" {
  description = "Security group ID for Application Servers in private subnets"
  value       = aws_security_group.application.id
}
