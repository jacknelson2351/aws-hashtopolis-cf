resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "hashtopolis" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false
  tags = { Name = "hashtopolis" }
}

resource "aws_vpc_endpoint" "autoscaling" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.autoscaling"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.main.id]
  security_group_ids  = [aws_security_group.lambda.id]
  private_dns_enabled = true
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}
