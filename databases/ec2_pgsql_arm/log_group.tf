################################################################################
# CloudWatch Log Group for PostgreSQL Logs
################################################################################

resource "aws_cloudwatch_log_group" "pgsql_logs" {
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
      Purpose     = "PostgreSQL-Logs"
    }
  )
}

