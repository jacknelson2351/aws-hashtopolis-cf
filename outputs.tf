output "server_instance_id" {
  value = aws_instance.server.id
}

output "ssm_shell" {
  value = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region}"
}

output "ssm_ui" {
  value = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"8080\"]}'"
}
