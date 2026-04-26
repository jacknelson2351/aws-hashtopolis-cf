resource "aws_security_group" "server" {
  name   = "hashtopolis-server"
  vpc_id = aws_vpc.main.id

  # Port 8080 open to world — agents have dynamic IPs, Lambda is outside the VPC.
  # All Hashtopolis endpoints require auth (JWT bearer token).
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "agents" {
  name   = "hashtopolis-agents"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
