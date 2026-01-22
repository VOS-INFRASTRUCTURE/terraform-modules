################################################################################
# Secrets Manager - PostgreSQL Passwords
#
# Purpose: Securely store PostgreSQL passwords
# Security: Passwords never stored in Terraform state or logs
################################################################################

################################################################################
# Generate Random Passwords (if not provided)
################################################################################

locals {
  generate_passwords = var.pgsql_postgres_password == "" || var.pgsql_password == ""
}

resource "random_password" "pgsql_postgres" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true
}

resource "random_password" "pgsql_user" {
  count   = local.generate_passwords ? 1 : 0
  length  = 32
  special = true
}

################################################################################
# Store PostgreSQL postgres password in Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "pgsql_postgres_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/pgsql-postgres-password"
  description             = "PostgreSQL postgres password for ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-postgres-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "PostgreSQL-Postgres-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "pgsql_postgres_password" {
  secret_id     = aws_secretsmanager_secret.pgsql_postgres_password.id
  secret_string = local.generate_passwords ? random_password.pgsql_postgres[0].result : var.pgsql_postgres_password
}

################################################################################
# Store PostgreSQL user password in Secrets Manager
################################################################################

resource "aws_secretsmanager_secret" "pgsql_user_password" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/pgsql-user-password"
  description             = "PostgreSQL user password for ${var.pgsql_user} on ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-user-password"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "PostgreSQL-User-Password"
    }
  )
}

resource "aws_secretsmanager_secret_version" "pgsql_user_password" {
  secret_id     = aws_secretsmanager_secret.pgsql_user_password.id
  secret_string = local.generate_passwords ? random_password.pgsql_user[0].result : var.pgsql_password
}

