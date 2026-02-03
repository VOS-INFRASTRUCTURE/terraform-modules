################################################################################
# Outputs for EC2 Qdrant Module
################################################################################

output "qdrant" {
  description = "Complete EC2 Qdrant instance configuration and connection details"
  value = {
    # Instance details
    instance = {
      id                = aws_instance.qdrant_ec2.id
      arn               = aws_instance.qdrant_ec2.arn
      private_ip        = aws_instance.qdrant_ec2.private_ip
      public_ip         = aws_instance.qdrant_ec2.public_ip
      availability_zone = aws_instance.qdrant_ec2.availability_zone
      instance_type     = aws_instance.qdrant_ec2.instance_type
      ami_id            = aws_instance.qdrant_ec2.ami
      ami_name          = data.aws_ami.ubuntu_arm64.name
      ami_description   = data.aws_ami.ubuntu_arm64.description
    }

    # Qdrant connection details
    connection = {
      private_ip = aws_instance.qdrant_ec2.private_ip
      http_port  = var.qdrant_http_port
      grpc_port  = var.qdrant_grpc_port

      # API endpoint URLs
      rest_api_url = "http://${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_http_port}"
      grpc_url     = "${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_grpc_port}"

      # Example curl commands
      health_check_cmd = "curl http://${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_http_port}/"
      collections_cmd  = "curl http://${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_http_port}/collections"
    }

    # Backup configuration
    backups = {
      enabled         = var.enable_automated_backups
      s3_bucket       = local.backup_bucket_name
      s3_bucket_arn   = local.backup_bucket_arn
      schedule        = var.backup_schedule
      retention_days  = var.backup_retention_days
      backup_path     = "s3://${local.backup_bucket_name}/qdrant-snapshots/${var.env}/${var.project_id}/"
      ebs_snapshots   = var.enable_ebs_snapshots
      cross_region_dr = var.enable_cross_region_snapshot_copy
      dr_region       = var.enable_cross_region_snapshot_copy ? var.snapshot_dr_region : null
    }

    # CloudWatch monitoring
    monitoring = var.enable_cloudwatch_monitoring ? {
      enabled        = true
      log_group      = aws_cloudwatch_log_group.qdrant_logs[0].name
      log_group_arn  = aws_cloudwatch_log_group.qdrant_logs[0].arn
      retention_days = var.cloudwatch_retention_days
      detailed_ec2   = var.enable_detailed_monitoring
    } : {
      enabled = false
    }

    # Security configuration
    security = {
      ebs_encrypted        = var.enable_ebs_encryption
      iam_role_arn         = aws_iam_role.qdrant_ec2.arn
      iam_role_id         = aws_iam_role.qdrant_ec2.id
      iam_instance_profile = aws_iam_instance_profile.qdrant_ec2.name
      security_group_ids   = var.security_group_ids
      ssm_access_enabled   = var.enable_ssm_access
      ssh_key_access       = var.enable_ssh_key_access
    }

    # IAM role
    iam_role = {
      name = aws_iam_role.qdrant_ec2.name
      arn  = aws_iam_role.qdrant_ec2.arn
    }
  }
}

output "connect_via_session_manager" {
  description = "Command to connect to the instance via AWS Systems Manager Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.qdrant_ec2.id}"
}

# Separate sensitive output for API keys (requires explicit query)
output "qdrant_api_keys" {
  description = <<-EOT
    Security Note: API keys are stored in AWS Secrets Manager.
    Retrieve them programmatically using the AWS CLI or SDK.

    To view: terraform output -json qdrant_api_keys
  EOT
  value = {
    # Secrets Manager references
    secrets = {
      api_key_secret_arn          = aws_secretsmanager_secret.qdrant_api_key.arn
      api_key_secret_id           = aws_secretsmanager_secret.qdrant_api_key.id

      # Commands to retrieve API keys
      get_api_key_cmd          = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.qdrant_api_key.id} --query SecretString --output text"
    }

    # Example usage with curl (retrieve key first)
    usage_examples = {
      get_collections     = "curl -H 'api-key: YOUR_API_KEY' http://${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_http_port}/collections"
      create_collection   = "curl -X PUT -H 'api-key: YOUR_API_KEY' -H 'Content-Type: application/json' http://${aws_instance.qdrant_ec2.private_ip}:${var.qdrant_http_port}/collections/my_collection -d '{\"vectors\":{\"size\":384,\"distance\":\"Cosine\"}}'"
    }
  }
  sensitive = true
}

