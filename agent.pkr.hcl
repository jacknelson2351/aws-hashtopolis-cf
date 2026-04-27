packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

source "amazon-ebs" "agent" {
  region        = "us-east-1"
  instance_type = "c5.xlarge"
  ssh_username  = "ubuntu"
  source_ami_filter {
    filters     = { name = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" }
    owners      = ["099720109477"]
    most_recent = true
  }
  ami_name = "hashtopolis-agent-{{timestamp}}"

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }
}

build {
  sources = ["source.amazon-ebs.agent"]
  provisioner "shell" {
    script          = "scripts/agent_init.sh"
    execute_command = "sudo bash '{{.Path}}'"
  }
}
