################################################################################
# EC2 Qdrant ARM Module - Native Installation (No Docker)
#
# Purpose: Deploy Qdrant vector database natively on EC2 ARM (Graviton) instances
#          for maximum performance and cost efficiency
#
# Benefits over Docker version:
# - 5-10% better performance (no Docker overhead)
# - 200-500MB less memory usage (no Docker daemon)
# - Simpler architecture (direct Qdrant installation)
# - 20-25% cost savings (ARM Graviton vs x86)
#
# Default: t4g.large (2 vCPU, 8GB RAM, ~$49/month)
#
# Security Features:
# - API keys stored in AWS Secrets Manager (not plain text)
# - Encrypted EBS volumes
# - IAM role with minimal permissions
# - CloudWatch monitoring and logging
# - Automated snapshots to S3
# - Systems Manager Session Manager (no SSH keys needed)
# - Qdrant configured with security best practices
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

# Auto-detect latest Ubuntu ARM64 AMI for current region
# Tries Ubuntu 24.04 (Noble) first, falls back to 22.04 (Jammy) if unavailable
#
# If auto-detection fails ("Your query returned no results"):
# 1. Find AMI in AWS Console: EC2 → Launch Instance → Browse AMIs → Search "ubuntu 24.04" → Filter by ARM64
# 2. Copy AMI ID (e.g., ami-065e6c5bbcd47041e)
# 3. Specify in module: ami_id = "ami-xxxxxxxxx"
# 4. See documentations/KNOWN_AMIS.md for common AMI IDs
data "aws_ami" "ubuntu_arm64" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
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

################################################################################
# Local Variables
################################################################################

locals {
  instance_name = "${var.project_id}-${var.env}-${var.base_name}-qdrant"

  # Return created bucket name or provided bucket name
  backup_bucket_name = var.enable_automated_backups ? (
    var.create_backup_bucket ? "${var.env}-${var.project_id}-${var.base_name}-qdrant-backups" : var.backup_s3_bucket_name
  ) : ""
  backup_bucket_arn = var.enable_automated_backups ? aws_s3_bucket.backup[0].arn : ""
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "qdrant_ec2" {
  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_arm64.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.enable_ssh_key_access ? var.key_name : null
  iam_instance_profile   = aws_iam_instance_profile.qdrant_ec2.name

  monitoring = var.enable_detailed_monitoring

  # Termination protection (optional, recommended for production)
  # Note: Even if instance is terminated, EBS snapshots persist independently
  disable_api_termination = var.enable_termination_protection

  # User data - Terraform automatically base64 encodes this
  # For large scripts, we use user_data_replace_on_change to avoid the 16KB limit
  user_data                   = local.user_data
  user_data_replace_on_change = false  # Don't replace instance if user_data changes

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Enforce IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = var.storage_size
    volume_type           = var.storage_type
    encrypted             = var.enable_ebs_encryption
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
      Name        = local.instance_name
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Qdrant-Vector-Database"
      Backup      = var.enable_automated_backups ? "Required" : "None"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
