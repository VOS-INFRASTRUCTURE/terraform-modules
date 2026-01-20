################################################################################
# EC2 MySQL ARM Module - Native Installation (No Docker)
#
# Purpose: Deploy MySQL 8.x natively on EC2 ARM (Graviton) instances
#          for maximum performance and cost efficiency
#
# Benefits over Docker version:
# - 5-10% better performance (no Docker overhead)
# - 200-500MB less memory usage (no Docker daemon)
# - Simpler architecture (direct MySQL installation)
# - 20-25% cost savings (ARM Graviton vs x86)
#
# Default: m7g.large (2 vCPU, 8GB RAM, ~$67/month)
#
# Security Features:
# - Passwords stored in AWS Secrets Manager (not plain text)
# - Encrypted EBS volumes
# - IAM role with minimal permissions
# - CloudWatch monitoring and logging
# - Automated backups to S3
# - Systems Manager Session Manager (no SSH keys needed)
# - MySQL configured with security best practices
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_region" "current" {}

################################################################################
# Local Variables
################################################################################

locals {
  instance_name = "${var.project_id}-${var.env}-${var.base_name}-mysql"

  # Return created bucket name or provided bucket name
  backup_bucket_name = var.enable_automated_backups ? (
    var.create_backup_bucket ? "${var.env}-${var.project_id}-${var.base_name}-mysql-backups" : var.backup_s3_bucket_name
  ) : ""
}

################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "mysql_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.enable_ssh_key_access ? var.key_name : null
  iam_instance_profile   = aws_iam_instance_profile.mysql_ec2.name

  monitoring = var.enable_detailed_monitoring

  # Termination protection (optional, recommended for production)
  # Note: Even if instance is terminated, EBS snapshots persist independently
  disable_api_termination = var.enable_termination_protection

  user_data = base64encode(local.user_data)

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
      Purpose     = "MySQL-Database"
      Backup      = var.enable_automated_backups ? "Required" : "None"
    }
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}
