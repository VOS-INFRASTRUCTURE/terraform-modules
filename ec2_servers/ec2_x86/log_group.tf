
################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "ec2_x86_logs" {
  count             = var.enable_cloudwatch_monitoring ? 1 : 0
  name              = "/aws/ec2/${local.instance_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-Logs"
    }
  )
}
