################################################################################
# EC2 Docker Server Module (ARM64/Graviton)
#
# Purpose: Deploy a general-purpose Docker host on ARM64/Graviton, using
# security best practices. ARM64 port of ec2-x86-docker — same shape and
# behavior, retargeted architecture (AMI, AWS CLI build, CloudWatch agent
# build, default instance type).
#
# Security Features:
# - Encrypted EBS volumes
# - IAM role with minimal permissions
# - CloudWatch monitoring and logging
# - Systems Manager Session Manager (no SSH keys needed)
################################################################################


################################################################################
# Local Variables
################################################################################

locals {
  instance_name = "${var.project_id}-${var.env}-${var.base_name}"
  ami_id        = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_2404_arm64.id
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "ec2_arm_docker" {
  ami                    = local.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.enable_ssh_key_access ? var.key_name : null
  iam_instance_profile   = aws_iam_instance_profile.ec2_arm_docker.name

  monitoring = var.enable_detailed_monitoring

  # Termination protection (optional, recommended for production)
  # Note: Even if instance is terminated, EBS snapshots persist independently
  disable_api_termination = var.enable_termination_protection

  # User data - Terraform automatically base64 encodes this, if you want to provide a base64-encoded string,
  # use user_data_base64 = local.user_data_base64
  user_data = local.user_data
  user_data_replace_on_change = false  # Don't replace instance if user_data changes

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = var.storage_size
    volume_type = var.storage_type
    encrypted   = var.enable_ebs_encryption
    # Delete volume when instance is terminated (safe - EBS snapshots persist independently)
    delete_on_termination = true

    tags = merge(
      var.tags,
      {
        Name        = "${local.instance_name}-root"
        Environment = var.env
        Project     = var.project_id
        ManagedBy   = "Terraform"
      }
    )
  }

  ebs_optimized = true

  tags = merge(
    var.tags,
    {
      Name         = local.instance_name
      Environment  = var.env
      Project      = var.project_id
      ManagedBy    = "Terraform"
      Purpose      = "Server"
      Architecture = "arm64"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
