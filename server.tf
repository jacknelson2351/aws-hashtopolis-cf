data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_eip" "server" {
  domain = "vpc"
}

resource "aws_eip_association" "server" {
  instance_id   = aws_instance.server.id
  allocation_id = aws_eip.server.id
}

resource "aws_instance" "server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.server.id]
  iam_instance_profile   = aws_iam_instance_profile.server.name

  user_data = templatefile("${path.module}/scripts/server_init.sh", {
    scaler_py            = file("${path.module}/scripts/scaler.py")
    asg_name             = "hashtopolis-agents"
    max_instances        = var.max_gpu_instances
    region               = var.region
    hashtopolis_username = var.hashtopolis_username
    password_secret_id   = aws_secretsmanager_secret.admin_password.id
    voucher_secret_id    = aws_secretsmanager_secret.voucher.id
  })

  tags = { Name = "hashtopolis-server" }
}
