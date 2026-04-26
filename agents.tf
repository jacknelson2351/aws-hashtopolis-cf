resource "aws_launch_template" "agent" {
  name_prefix            = "hashtopolis-agent-"
  image_id               = var.agent_ami_id
  instance_type          = "g4dn.xlarge"
  vpc_security_group_ids = [aws_security_group.agents.id]

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "terminate"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    python3 /opt/hashtopolis/hashtopolis.zip \
      --url http://${aws_instance.server.private_ip}:8080/api/server.php \
      --voucher ${var.hashtopolis_voucher} \
      --nogui
  EOF
  )
}

resource "aws_autoscaling_group" "agents" {
  name                = "hashtopolis-agents"
  min_size            = 0
  max_size            = var.max_gpu_instances
  desired_capacity    = 0
  vpc_zone_identifier = [aws_subnet.main.id]

  launch_template {
    id      = aws_launch_template.agent.id
    version = "$Latest"
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
