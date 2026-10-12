data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

locals {
  # Select 2 availability zones (either user-provided or auto-discovered)
  azs = var.availability_zones != null ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, 2)

  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : 2) : 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

  tags = merge(
    var.tags,
    {
      "Name" = var.name
    }
  )
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-igw"
    }
  )
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-public-${local.azs[count.index]}"
      "Tier" = "public"
      "Role" = "load-balancer-reverse-proxy"
    }
  )
}

resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-private-${local.azs[count.index]}"
      "Tier" = "private"
      "Role" = "application-server"
    }
  )
}

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-nat-gw-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-public-rt"
    }
  )
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = var.single_nat_gateway ? 1 : 2
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.tags,
    {
      "Name" = var.single_nat_gateway ? "${var.name}-private-rt" : "${var.name}-private-rt-${local.azs[count.index]}"
    }
  )
}

resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : 2) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = var.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[count.index].id
}

# Keeps all S3 API traffic inside the AWS private backbone network.
# Enhances security by bypassing public internet and reduces cost by avoiding
# NAT Gateway data processing charges.
resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_s3_endpoint ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    [aws_route_table.public.id],
    aws_route_table.private[*].id
  )

  tags = merge(
    var.tags,
    {
      "Name" = "${var.name}-s3-gateway-endpoint"
    }
  )
}
