resource "aws_iam_role" "server" {
  name = "hashtopolis-server"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "server_ssm" {
  role       = aws_iam_role.server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "server" {
  role = aws_iam_role.server.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [
          aws_secretsmanager_secret.admin_password.arn,
          aws_secretsmanager_secret.voucher.arn,
        ]
      },
      {
        Effect = "Allow"
        Action = ["secretsmanager:PutSecretValue"]
        Resource = [
          aws_secretsmanager_secret.voucher.arn,
          aws_secretsmanager_secret.admin_password.arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity"]
        Resource = aws_autoscaling_group.agents.arn
      },
    ]
  })
}

resource "aws_iam_instance_profile" "server" {
  name = "hashtopolis-server"
  role = aws_iam_role.server.name
}

resource "aws_iam_group" "viewers" {
  name = "hashtopolis-viewers"
}

resource "aws_iam_group_policy" "viewers_ssm" {
  group = aws_iam_group.viewers.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "ssm:StartSession"
        Resource = [
          aws_instance.server.arn,
          "arn:aws:ssm:${var.region}::document/AWS-StartPortForwardingSession"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "ssm:TerminateSession"
        Resource = "arn:aws:ssm:*:*:session/$${aws:username}-*"
      }
    ]
  })
}

resource "aws_iam_role" "agent" {
  name = "hashtopolis-agent"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "agent_ssm" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "agent" {
  role = aws_iam_role.agent.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.voucher.arn
    }]
  })
}

resource "aws_iam_instance_profile" "agent" {
  name = "hashtopolis-agent"
  role = aws_iam_role.agent.name
}
