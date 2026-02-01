
locals {
  # Generate secure random passwords if not provided
  generate_passwords = var.mysql_root_password == "" || var.mysql_password == ""
}

################################################################################
# Secrets Manager - Secure Password Storage
################################################################################

# Generate secure random passwords
resource "random_password" "mysql_root" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true

  # Ensure password doesn't start/end with special chars (MySQL compatibility)
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_password" "mysql_user" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Store MySQL root password in Secrets Manager
resource "aws_secretsmanager_secret" "mysql_root_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/mysql-root-password"
  description             = "MySQL root password for ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-root-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-Root-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "mysql_root_password" {
  secret_id     = aws_secretsmanager_secret.mysql_root_password.id
  secret_string = local.generate_passwords ? random_password.mysql_root[0].result : var.mysql_root_password
}

# Store MySQL user password in Secrets Manager
resource "aws_secretsmanager_secret" "mysql_user_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/mysql-user-password"
  description             = "MySQL user password for ${var.mysql_user} on ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-user-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "MySQL-User-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "mysql_user_password" {
  secret_id     = aws_secretsmanager_secret.mysql_user_password.id
  secret_string = local.generate_passwords ? random_password.mysql_user[0].result : var.mysql_password
}
