data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "scaler" {
  filename         = data.archive_file.lambda.output_path
  function_name    = "hashtopolis-scaler"
  role             = aws_iam_role.lambda.arn
  handler          = "scaler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      HASHTOPOLIS_URL      = "http://${aws_eip.server.public_ip}:8080"
      ASG_NAME             = aws_autoscaling_group.agents.name
      MAX_INSTANCES        = tostring(var.max_gpu_instances)
      HASHTOPOLIS_USERNAME = var.hashtopolis_username
      HASHTOPOLIS_PASSWORD = var.hashtopolis_password
      REGION               = var.region
    }
  }
}

resource "aws_cloudwatch_event_rule" "scaler" {
  name                = "hashtopolis-scaler"
  schedule_expression = "rate(1 minute)"
}

resource "aws_cloudwatch_event_target" "scaler" {
  rule      = aws_cloudwatch_event_rule.scaler.name
  target_id = "hashtopolis-scaler"
  arn       = aws_lambda_function.scaler.arn
}

resource "aws_lambda_permission" "scaler" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.scaler.arn
}
