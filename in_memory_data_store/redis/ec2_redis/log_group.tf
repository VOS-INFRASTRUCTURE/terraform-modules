
################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "redis" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  # Default kept as-is (no base_name) so existing hosts keep their log group.
  name              = var.log_group_name != "" ? var.log_group_name : "/aws/ec2/${var.env}-${var.project_id}-redis"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Redis-Logs"
    },
    var.tags
  )
}
