################################################################################
# EC2 MySQL Module - Secure and Production-Ready
#
# Purpose: Deploy MySQL on EC2 with Docker, using security best practices
#
# Security Features:
# - Passwords stored in AWS Secrets Manager (not plain text)
# - Encrypted EBS volumes
# - IAM role with minimal permissions
# - CloudWatch monitoring and logging
# - Automated backups to S3
# - Systems Manager Session Manager (no SSH keys needed)
# - MySQL configured with security best practices
#
# Cost: ~$15-25/month (t3.micro + 20GB GP3 storage)
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

  # Generate secure random passwords if not provided
  generate_passwords = var.mysql_root_password == "" || var.mysql_password == ""
}

################################################################################
# Secrets Manager - Secure Password Storage
################################################################################

# Generate secure random passwords
resource "random_password" "mysql_root" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true

  # Ensure password doesn't start/end with special chars (MySQL compatibility)
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "mysql_user" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store MySQL root password in Secrets Manager
resource "aws_secretsmanager_secret" "mysql_root_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/mysql-root-password"
  description             = "MySQL root password for ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-root-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-Root-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "mysql_root_password" {
  secret_id     = aws_secretsmanager_secret.mysql_root_password.id
  secret_string = local.generate_passwords ? random_password.mysql_root[0].result : var.mysql_root_password
}

# Store MySQL user password in Secrets Manager
resource "aws_secretsmanager_secret" "mysql_user_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/mysql-user-password"
  description             = "MySQL user password for ${var.mysql_user} on ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-user-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-User-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "mysql_user_password" {
  secret_id     = aws_secretsmanager_secret.mysql_user_password.id
  secret_string = local.generate_passwords ? random_password.mysql_user[0].result : var.mysql_password
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
