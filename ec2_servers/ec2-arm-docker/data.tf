################################################################################
# AMI Lookup — Ubuntu 24.04 LTS ARM64
################################################################################
# Used only when var.ami_id is left empty. Matches several known name
# patterns for the 24.04 (Noble) ARM64 image, since the exact naming varies
# by storage backend (standard vs gp3) — picks the most recent match.
#
# If this returns no results ("Your query returned no results"):
# 1. Find the AMI in the AWS Console: EC2 -> Launch Instance -> Browse AMIs ->
#    search "ubuntu 24.04" -> filter by ARM64
# 2. Pass it explicitly: ami_id = "ami-xxxxxxxxx"

data "aws_ami" "ubuntu_2404_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd/ubuntu-noble-24.04-arm64-server-*",
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*",
      "Ubuntu Server 24.04 LTS*",
    ]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}
