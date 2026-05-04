resource "aws_launch_template" "agent" {
  name_prefix   = "hashtopolis-agent-"
  image_id      = var.agent_ami_id
  instance_type = "g4dn.xlarge"

  iam_instance_profile {
    name = aws_iam_instance_profile.agent.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.agents.id]
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      instance_interruption_behavior = "terminate"
    }
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    apt-get update -y
    apt-get install -y python3-boto3

    mkdir -p /opt/hashtopolis

    cat >/opt/hashtopolis/start-agent.sh <<'SCRIPT'
    #!/bin/bash
    set -e

    cd /opt/hashtopolis

    VOUCHER=""
    while [ -z "$VOUCHER" ]; do
      VOUCHER=$(python3 -c "import boto3,sys; v=boto3.client('secretsmanager',region_name='${var.region}').get_secret_value(SecretId='${aws_secretsmanager_secret.voucher.id}').get('SecretString',''); print(v)" 2>/dev/null || true)
      if [ -z "$VOUCHER" ]; then
        echo "waiting for voucher secret to be populated..."
        sleep 30
      fi
    done

    until curl -fsS "http://${aws_instance.server.private_ip}:8080/agents.php?download=1" -o hashtopolis.zip; do
      sleep 10
    done

    exec /usr/bin/python3 /opt/hashtopolis/hashtopolis.zip \
      --url "http://${aws_instance.server.private_ip}:8080/api/server.php" \
      --voucher "$VOUCHER"
    SCRIPT

    chmod +x /opt/hashtopolis/start-agent.sh

    cat >/etc/systemd/system/hashtopolis-agent.service <<'SERVICE'
    [Unit]
    Description=Hashtopolis Agent
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=simple
    Restart=always
    RestartSec=10
    WorkingDirectory=/opt/hashtopolis
    ExecStart=/opt/hashtopolis/start-agent.sh

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now hashtopolis-agent.service
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
