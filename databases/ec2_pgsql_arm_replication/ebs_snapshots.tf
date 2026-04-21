################################################################################
# EBS Snapshot Backups (AWS Data Lifecycle Manager)
#
# Purpose: Automated EBS volume snapshots for disaster recovery
#
# What's backed up:
# - PostgreSQL database backups (pgsqldump): To S3 hourly (via cron)
# - EBS volume snapshots: Complete EC2 disk image (via DLM)
#
# Why both?
# - PostgreSQL backups: Fast database-level restore, cross-region possible
# - EBS snapshots: Full system restore including OS, configs
#
# Recovery scenarios:
# - Database corruption: Restore from S3 PostgreSQL backup
# - EC2 instance failure: Launch new EC2 from EBS snapshot
# - Complete disaster: Both available for maximum flexibility
#
# Cross-Region Disaster Recovery:
# - enable_cross_region_snapshot_copy: true/false
# - snapshot_dr_region: Target region for DR copies (e.g., "us-east-1")
# - snapshot_dr_retention_days: How long to keep DR copies
#
# Default: Snapshots stored in same region only
# With DR: Snapshots automatically copied to secondary region
#
# Storage locations:
# - Primary snapshots: Same region as EC2 instance
# - DR snapshots: Specified in snapshot_dr_region variable
# - Can restore from either region based on disaster scenario
################################################################################

################################################################################
# IAM Role for DLM
################################################################################

resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enable_ebs_snapshots ? 1 : 0

  name = "${var.env}-${var.project_id}-${var.base_name}-pgsql-dlm-role"

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

  name = "${var.env}-${var.project_id}-${var.base_name}-pgsql-dlm-policy"
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
          "ec2:DescribeSnapshots",
          "ec2:CopySnapshot",
          "ec2:ModifySnapshotAttribute"
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

resource "aws_dlm_lifecycle_policy" "pgsql_ebs_snapshots" {
  count = var.enable_ebs_snapshots ? 1 : 0

  description        = "Automated EBS snapshots for ${local.instance_name}"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    # Target EBS volumes attached to this specific PostgreSQL instance
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
        Purpose      = "PostgreSQL-EBS-Backup"
        ManagedBy    = "Terraform"
      }

      copy_tags = true

      # Cross-region copy for disaster recovery (optional)
      dynamic "cross_region_copy_rule" {
        for_each = var.enable_cross_region_snapshot_copy && var.snapshot_dr_region != "" ? [1] : []

        content {
          target    = var.snapshot_dr_region
          encrypted = true

          retain_rule {
            interval      = var.snapshot_dr_retention_days
            interval_unit = "DAYS"
          }

          copy_tags = true
        }
      }
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

