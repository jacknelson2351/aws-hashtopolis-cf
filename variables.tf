variable "region" {
  default = "us-east-1"
}

variable "agent_ami_id" {
  description = "AMI from Packer build (see README)"
}

variable "max_gpu_instances" {
  default = 5
}

variable "hashtopolis_voucher" {
  description = "Agent voucher from Hashtopolis UI (Agents > New Agent). Leave blank on first deploy."
  default     = ""
}

variable "hashtopolis_api_key" {
  description = "JWT API token from Hashtopolis UI (Config > API Tokens). Leave blank on first deploy."
  sensitive   = true
  default     = ""
}
