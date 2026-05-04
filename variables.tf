variable "region" {
  default = "us-east-1"
}

variable "availability_zone" {
  description = "AZ to deploy the subnet and instances into. Must be within var.region."
  default     = "us-east-1b"
}

variable "agent_ami_id" {
  description = "AMI from Packer build (see README)"
}

variable "max_gpu_instances" {
  default = 5
}

variable "local_ui_port" {
  description = "Local port used by the SSM tunnel for the Hashtopolis web UI. The server still listens on 8080."
  default     = 8082
}

variable "hashtopolis_username" {
  description = "Hashtopolis web username used by the server-side scaler to request short-lived APIv2 JWTs."
  default     = "admin"
}
