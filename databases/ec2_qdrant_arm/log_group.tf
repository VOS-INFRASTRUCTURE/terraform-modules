################################################################################
# CloudWatch Log Group for Qdrant Logs
#
# Purpose: Centralize Qdrant logs in CloudWatch for monitoring and debugging
#
# Logs captured:
# - Qdrant application logs
# - System logs (syslog)
# - Setup script logs
# - Backup logs
################################################################################

resource "aws_cloudwatch_log_group" "qdrant_logs" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/ec2/${local.instance_name}"
  retention_in_days = var.cloudwatch_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Qdrant-Logs"
    }
  )
}

