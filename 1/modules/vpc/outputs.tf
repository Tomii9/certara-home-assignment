output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value       = aws_vpc.this.arn
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of the 2 public subnets"
  value       = aws_subnet.public[*].id
}

output "public_subnet_arns" {
  description = "List of ARNs of the 2 public subnets"
  value       = aws_subnet.public[*].arn
}

output "private_subnet_ids" {
  description = "List of IDs of the 2 private subnets"
  value       = aws_subnet.private[*].id
}

output "private_subnet_arns" {
  description = "List of ARNs of the 2 private subnets"
  value       = aws_subnet.private[*].arn
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.this.id
}

output "nat_gateway_ids" {
  description = "List of IDs of the NAT Gateway(s)"
  value       = aws_nat_gateway.this[*].id
}

output "nat_public_ips" {
  description = "List of Elastic IPs associated with the NAT Gateway(s)"
  value       = aws_eip.nat[*].public_ip
}

output "public_route_table_id" {
  description = "The ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "List of IDs of the private route table(s)"
  value       = aws_route_table.private[*].id
}

output "s3_vpc_endpoint_id" {
  description = "The ID of the S3 VPC Gateway Endpoint"
  value       = try(aws_vpc_endpoint.s3[0].id, null)
}

output "s3_vpc_endpoint_prefix_list_id" {
  description = "The prefix list ID of the S3 VPC Gateway Endpoint (useful for security groups or route tables)"
  value       = try(aws_vpc_endpoint.s3[0].prefix_list_id, null)
}

output "availability_zones" {
  description = "The availability zones used for the subnets"
  value       = local.azs
}
