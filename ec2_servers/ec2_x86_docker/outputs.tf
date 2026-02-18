################################################################################
# Outputs for EC2  Module
################################################################################

output "server" {
  description = "Complete EC2  instance configuration and connection details"
  value = {
    # Instance details
    instance = {
      id                = aws_instance.ec2_x86_docker.id
      arn               = aws_instance.ec2_x86_docker.arn
      private_ip        = aws_instance.ec2_x86_docker.private_ip
      public_ip         = aws_instance.ec2_x86_docker.public_ip
      availability_zone = aws_instance.ec2_x86_docker.availability_zone
      instance_type     = aws_instance.ec2_x86_docker.instance_type
    }

    # Security configuration
    security = {
      ebs_encrypted        = var.enable_ebs_encryption
      iam_role_arn         = aws_iam_role.ec2_x86_docker.arn
      iam_role_id         = aws_iam_role.ec2_x86_docker.id
      iam_instance_profile = aws_iam_instance_profile.ec2_x86_docker.name
      security_group_ids   = var.security_group_ids
      ssm_access_enabled   = var.enable_ssm_access
      ssh_key_access       = var.enable_ssh_key_access
    }

    # Monitoring configuration
    monitoring = {
      enabled            = var.enable_cloudwatch_monitoring
      log_group_name     = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : null
      log_group_arn      = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].arn : null
      log_retention_days = var.log_retention_days
    }

    # Backup configuration
    backup = {
      # EBS volume snapshots (full disk image)
      ebs_snapshots = {
        enabled             = var.enable_ebs_snapshots
        interval_hours      = var.enable_ebs_snapshots ? var.ebs_snapshot_interval_hours : null
        snapshot_time       = var.enable_ebs_snapshots ? var.ebs_snapshot_time : null
        retention_count     = var.enable_ebs_snapshots ? var.ebs_snapshot_retention_count : null
        dlm_policy_id       = var.enable_ebs_snapshots ? aws_dlm_lifecycle_policy.mysql_ebs_snapshots[0].id : null
        dlm_policy_arn      = var.enable_ebs_snapshots ? aws_dlm_lifecycle_policy.mysql_ebs_snapshots[0].arn : null
      }

      # Restore instructions
      restore_instructions = {
        ebs_from_snapshot = var.enable_ebs_snapshots ? "aws ec2 describe-snapshots --filters 'Name=tag:Name,Values=${local.instance_name}-dlm-policy' --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize]' --output table" : "EBS snapshots not enabled"
      }
    }

    # Access instructions
    access = {
      ssm_session_command = var.enable_ssm_access ? "aws ssm start-session --target ${aws_instance.ec2_x86_docker.id}" : "SSM access not enabled"
      ssh_command         = var.enable_ssh_key_access && var.key_name != "" ? "ssh -i /path/to/${var.key_name}.pem ubuntu@${aws_instance.ec2_x86_docker.private_ip}" : "SSH key access not configured"
    }
  }

  sensitive = false
}
