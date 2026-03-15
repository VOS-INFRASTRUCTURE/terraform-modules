################################################################################
# EBS Snapshot Backups (AWS Data Lifecycle Manager)
#
# Purpose: Automated EBS volume snapshots for disaster recovery
#
# What's backed up:
# - MySQL database backups (mysqldump): To S3 hourly (via cron)
# - EBS volume snapshots: Complete EC2 disk image (via DLM)
#
# Why both?
# - MySQL backups: Fast database-level restore, cross-region possible
# - EBS snapshots: Full system restore including OS, Docker, configs
#
# Recovery scenarios:
# - Database corruption: Restore from S3 MySQL backup
# - EC2 instance failure: Launch new EC2 from EBS snapshot
# - Complete disaster: Both available for maximum flexibility
################################################################################

################################################################################
# IAM Role for DLM
################################################################################

resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enable_ebs_snapshots ? 1 : 0

  name = "${var.env}-${var.project_id}-${var.base_name}-mysql-dlm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-dlm-role"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "EBS-Snapshots"
    }
  )
}

################################################################################
# IAM Policy for DLM
################################################################################

resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  count = var.enable_ebs_snapshots ? 1 : 0

  name = "${var.env}-${var.project_id}-${var.base_name}-mysql-dlm-policy"
  role = aws_iam_role.dlm_lifecycle_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags"
        ]
        Resource = "arn:aws:ec2:*::snapshot/*"
      }
    ]
  })
}

################################################################################
# DLM Lifecycle Policy for EBS Snapshots
################################################################################

resource "aws_dlm_lifecycle_policy" "mysql_ebs_snapshots" {
  count = var.enable_ebs_snapshots ? 1 : 0

  description        = "Automated EBS snapshots for ${local.instance_name}"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    # Target EBS volumes attached to this specific MySQL instance
    target_tags = {
      Name = "${local.instance_name}-root"
    }

    schedule {
      name = "Daily snapshots at ${var.ebs_snapshot_time}"

      create_rule {
        interval      = var.ebs_snapshot_interval_hours
        interval_unit = "HOURS"
        times         = [var.ebs_snapshot_time]
      }

      retain_rule {
        count = var.ebs_snapshot_retention_count
      }

      tags_to_add = {
        SnapshotType = "DLM-Automated"
        Environment  = var.env
        Project      = var.project_id
        Purpose      = "MySQL-EBS-Backup"
        ManagedBy    = "Terraform"
      }

      copy_tags = true
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-dlm-policy"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "EBS-Snapshots"
    }
  )
}

