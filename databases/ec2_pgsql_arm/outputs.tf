################################################################################
# Outputs for EC2 PostgreSQL Module
################################################################################

output "pgsql" {
  description = "Complete EC2 PostgreSQL instance configuration and connection details"
  value = {
    # Instance details
    instance = {
      id                = aws_instance.pgsql_ec2.id
      arn               = aws_instance.pgsql_ec2.arn
      private_ip        = aws_instance.pgsql_ec2.private_ip
      public_ip         = aws_instance.pgsql_ec2.public_ip
      availability_zone = aws_instance.pgsql_ec2.availability_zone
      instance_type     = aws_instance.pgsql_ec2.instance_type
      ami_id            = aws_instance.pgsql_ec2.ami
      ami_name          = data.aws_ami.ubuntu_arm64.name
      ami_description   = data.aws_ami.ubuntu_arm64.description
    }

    # PostgreSQL connection details
    connection = {
      host     = aws_instance.pgsql_ec2.private_ip
      port     = 5432
      database = var.pgsql_database
      user     = var.pgsql_user

      # Connection string examples (password must be retrieved separately)
      psql_command = "psql -h ${aws_instance.pgsql_ec2.private_ip} -p 5432 -U ${var.pgsql_user} -d ${var.pgsql_database}"
      jdbc_url     = "jdbc:postgresql://${aws_instance.pgsql_ec2.private_ip}:5432/${var.pgsql_database}"
      node_url     = "postgresql://${var.pgsql_user}:PASSWORD@${aws_instance.pgsql_ec2.private_ip}:5432/${var.pgsql_database}"
      python_url   = "postgresql://${var.pgsql_user}:PASSWORD@${aws_instance.pgsql_ec2.private_ip}:5432/${var.pgsql_database}"
      django_dsn   = "postgres://${var.pgsql_user}:PASSWORD@${aws_instance.pgsql_ec2.private_ip}:5432/${var.pgsql_database}"
    }

    # Secrets Manager references
    secrets = {
      postgres_password_secret_arn = aws_secretsmanager_secret.pgsql_postgres_password.arn
      postgres_password_secret_id  = aws_secretsmanager_secret.pgsql_postgres_password.id
      user_password_secret_arn     = aws_secretsmanager_secret.pgsql_user_password.arn
      user_password_secret_id      = aws_secretsmanager_secret.pgsql_user_password.id

      # Command to retrieve passwords
      get_postgres_password_cmd = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_postgres_password.id} --query SecretString --output text"
      get_user_password_cmd     = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_user_password.id} --query SecretString --output text"
    }

    # Backup configuration
    backups = var.enable_automated_backups ? {
      enabled         = true
      s3_bucket       = local.backup_bucket_name
      schedule        = var.backup_schedule
      retention_days  = var.backup_retention_days
      backup_path     = "s3://${local.backup_bucket_name}/pgsql-backups/${var.env}/${var.project_id}/"
      ebs_snapshots   = var.enable_ebs_snapshots
      cross_region_dr = var.enable_cross_region_snapshot_copy
      dr_region       = var.enable_cross_region_snapshot_copy ? var.snapshot_dr_region : null
    } : {
      enabled = false
    }

    # CloudWatch monitoring
    monitoring = var.enable_cloudwatch_monitoring ? {
      enabled         = true
      log_group       = aws_cloudwatch_log_group.pgsql_logs[0].name
      log_group_arn   = aws_cloudwatch_log_group.pgsql_logs[0].arn
      retention_days  = var.cloudwatch_retention_days
      detailed_ec2    = var.enable_detailed_monitoring
    } : {
      enabled = false
    }

    # IAM role
    iam_role = {
      name = aws_iam_role.pgsql_ec2.name
      arn  = aws_iam_role.pgsql_ec2.arn
    }
  }
}

output "connect_via_session_manager" {
  description = "Command to connect to the instance via AWS Systems Manager Session Manager"
  value       = "aws ssm start-session --target ${aws_instance.pgsql_ec2.id}"
}

output "postgres_password_retrieval" {
  description = "Command to retrieve postgres password from Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_postgres_password.id} --query SecretString --output text"
}

output "user_password_retrieval" {
  description = "Command to retrieve user password from Secrets Manager"
  value       = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_user_password.id} --query SecretString --output text"
}

