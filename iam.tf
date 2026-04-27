# Server role — SSM access only (no SSH needed)
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

resource "aws_iam_instance_profile" "server" {
  name = "hashtopolis-server"
  role = aws_iam_role.server.name
}

# Viewer group — SSM port-forward only, no shell access
resource "aws_iam_group" "viewers" {
  name = "hashtopolis-viewers"
}

resource "aws_iam_group_policy" "viewers_ssm" {
  group = aws_iam_group.viewers.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ssm:StartSession"
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


# Agent role — SSM access for debugging
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

resource "aws_iam_instance_profile" "agent" {
  name = "hashtopolis-agent"
  role = aws_iam_role.agent.name
}

# Lambda role — ASG control + CloudWatch logs
resource "aws_iam_role" "lambda" {
  name = "hashtopolis-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["autoscaling:SetDesiredCapacity", "autoscaling:DescribeAutoScalingGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*"
      },
    ]
  })
}
