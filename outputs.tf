output "server_instance_id" {
  value = aws_instance.server.id
}

output "ssm_shell" {
  value       = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region}"
  description = "Run with: terraform output -raw ssm_shell"
}

output "ssm_ui" {
  value       = "aws ssm start-session --target ${aws_instance.server.id} --region ${var.region} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"8080\"],\"localPortNumber\":[\"${var.local_ui_port}\"]}'   then open http://localhost:${var.local_ui_port}"
  description = "Run with: terraform output -raw ssm_ui"
}
