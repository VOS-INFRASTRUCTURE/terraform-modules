################################################################################
# Outputs for EC2 MySQL Module
################################################################################

output "mysql" {
  description = "Complete EC2 MySQL instance configuration and connection details"
  value = {
    # Instance details
    instance = {
      id                = aws_instance.mysql_ec2.id
      arn               = aws_instance.mysql_ec2.arn
      private_ip        = aws_instance.mysql_ec2.private_ip
      public_ip         = aws_instance.mysql_ec2.public_ip
      availability_zone = aws_instance.mysql_ec2.availability_zone
      instance_type     = aws_instance.mysql_ec2.instance_type
    }

    # MySQL connection details
    connection = {
      host     = aws_instance.mysql_ec2.private_ip
      port     = 3306
      database = var.mysql_database
      user     = var.mysql_user

      # Connection string examples (password must be retrieved separately)
      mysql_cli_command = "mysql -h ${aws_instance.mysql_ec2.private_ip} -P 3306 -u ${var.mysql_user} -p ${var.mysql_database}"
      jdbc_url          = "jdbc:mysql://${aws_instance.mysql_ec2.private_ip}:3306/${var.mysql_database}"
      node_js_url       = "mysql://${var.mysql_user}:***PASSWORD***@${aws_instance.mysql_ec2.private_ip}:3306/${var.mysql_database}"
      python_url        = "mysql+pymysql://${var.mysql_user}:***PASSWORD***@${aws_instance.mysql_ec2.private_ip}:3306/${var.mysql_database}"
      php_dsn           = "mysql:host=${aws_instance.mysql_ec2.private_ip};port=3306;dbname=${var.mysql_database}"
    }

    # Secrets Manager ARNs
    secrets = {
      root_password_secret_arn = aws_secretsmanager_secret.mysql_root_password.arn
      root_password_secret_name = aws_secretsmanager_secret.mysql_root_password.name
      user_password_secret_arn = aws_secretsmanager_secret.mysql_user_password.arn
      user_password_secret_name = aws_secretsmanager_secret.mysql_user_password.name

      # Commands to retrieve passwords
      get_root_password_command = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} --query SecretString --output text"
      get_user_password_command = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.mysql_user_password.name} --query SecretString --output text"
    }

    # Security configuration
    security = {
      ebs_encrypted        = var.enable_ebs_encryption
      iam_role_arn         = aws_iam_role.mysql_ec2.arn
      iam_instance_profile = aws_iam_instance_profile.mysql_ec2.name
      security_group_ids   = var.security_group_ids
      ssm_access_enabled   = var.enable_ssm_access
      ssh_key_access       = var.enable_ssh_key_access
    }

    # Monitoring configuration
    monitoring = {
      enabled            = var.enable_cloudwatch_monitoring
      log_group_name     = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : null
      log_group_arn      = var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].arn : null
      log_retention_days = var.log_retention_days
    }

    # Backup configuration
    backup = {
      enabled            = var.enable_automated_backups
      s3_bucket          = var.backup_s3_bucket_name
      schedule           = var.backup_schedule
      retention_days     = var.backup_retention_days
    }

    # MySQL configuration
    mysql_config = {
      version           = var.mysql_version
      database          = var.mysql_database
      user              = var.mysql_user
      max_connections   = var.mysql_max_connections
      buffer_pool_size  = var.innodb_buffer_pool_size
    }

    # Access instructions
    access = {
      ssm_session_command = var.enable_ssm_access ? "aws ssm start-session --target ${aws_instance.mysql_ec2.id}" : "SSM access not enabled"
      ssh_command         = var.enable_ssh_key_access && var.key_name != "" ? "ssh -i /path/to/${var.key_name}.pem ubuntu@${aws_instance.mysql_ec2.private_ip}" : "SSH key access not configured"

      # MySQL client access (after connecting to instance)
      mysql_client_commands = {
        connect_as_root = "docker exec -it mysql-server mysql -u root -p"
        connect_as_user = "docker exec -it mysql-server mysql -u ${var.mysql_user} -p ${var.mysql_database}"
        view_logs       = "docker logs mysql-server -f"
        container_status = "docker ps | grep mysql-server"
      }
    }

    # Application configuration examples
    app_config_examples = {
      node_js = {
        package = "mysql2"
        install = "npm install mysql2"
        connection = <<-EOF
          const mysql = require('mysql2/promise');
          const connection = await mysql.createConnection({
            host: '${aws_instance.mysql_ec2.private_ip}',
            port: 3306,
            user: '${var.mysql_user}',
            password: process.env.MYSQL_PASSWORD, // From Secrets Manager
            database: '${var.mysql_database}'
          });
        EOF
      }
      python = {
        package = "pymysql"
        install = "pip install pymysql"
        connection = <<-EOF
          import pymysql
          import os
          connection = pymysql.connect(
              host='${aws_instance.mysql_ec2.private_ip}',
              port=3306,
              user='${var.mysql_user}',
              password=os.environ['MYSQL_PASSWORD'],  # From Secrets Manager
              database='${var.mysql_database}'
          )
        EOF
      }
      php = {
        package = "Built-in mysqli or PDO"
        install = "Already included in PHP"
        connection = <<-EOF
          $mysqli = new mysqli(
              '${aws_instance.mysql_ec2.private_ip}',
              '${var.mysql_user}',
              getenv('MYSQL_PASSWORD'),  // From Secrets Manager
              '${var.mysql_database}',
              3306
          );
        EOF
      }
      environment_variables = {
        MYSQL_HOST     = aws_instance.mysql_ec2.private_ip
        MYSQL_PORT     = "3306"
        MYSQL_DATABASE = var.mysql_database
        MYSQL_USER     = var.mysql_user
        MYSQL_PASSWORD = "***RETRIEVE_FROM_SECRETS_MANAGER***"
      }
    }
  }

  sensitive = false
}

# Separate sensitive output for passwords (requires explicit query)
output "mysql_passwords" {
  description = <<-EOT
    MySQL passwords (sensitive - only shown if explicitly queried).

    To view: terraform output -json mysql_passwords | jq -r '.root_password'

    Security Note: Passwords are stored in AWS Secrets Manager.
    Retrieve them programmatically using the AWS CLI or SDK.
  EOT
  value = {
    root_password = local.generate_passwords ? random_password.mysql_root[0].result : var.mysql_root_password
    user_password = local.generate_passwords ? random_password.mysql_user[0].result : var.mysql_password

    # Alternative: Retrieve from Secrets Manager (recommended)
    retrieve_root_password = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} --query SecretString --output text"
    retrieve_user_password = "aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.mysql_user_password.name} --query SecretString --output text"
  }
  sensitive = true
}

