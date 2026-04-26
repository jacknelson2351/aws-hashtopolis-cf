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
  instance_type = "g4dn.xlarge"
  ssh_username  = "ubuntu"
  source_ami_filter {
    filters     = { name = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" }
    owners      = ["099720109477"]
    most_recent = true
  }
  ami_name = "hashtopolis-agent-{{timestamp}}"
}

build {
  sources = ["source.amazon-ebs.agent"]
  provisioner "shell" {
    inline = [
      "sudo apt-get update -y",
      "wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2204/x86_64/cuda-keyring_1.1-1_all.deb",
      "sudo dpkg -i cuda-keyring_1.1-1_all.deb && sudo apt-get update -y",
      "sudo apt-get install -y cuda-toolkit-12-3 nvidia-driver-545 hashcat python3 python3-pip",
      "sudo pip3 install requests psutil",
      "sudo mkdir -p /opt/hashtopolis",
      "wget -q $(curl -s https://api.github.com/repos/hashtopolis/client/releases/latest | grep browser_download_url | grep .zip | cut -d'\"' -f4) -O /opt/hashtopolis/hashtopolis.zip",
    ]
  }
}
