################################################################################
# Secrets Manager - Qdrant API Keys
#
# Purpose: Store Qdrant API keys securely in AWS Secrets Manager
# Security: Keys are never stored in plain text or in Terraform state
################################################################################

################################################################################
# Random Password Generation (if not provided)
################################################################################

resource "random_password" "qdrant_api_key" {
  length  = 32
  special = true
}

resource "random_password" "qdrant_read_only_key" {
  length  = 32
  special = true
}

################################################################################
# Secrets Manager - Qdrant API Key (Full Access)
################################################################################

resource "aws_secretsmanager_secret" "qdrant_api_key" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/qdrant-api-key"
  description             = "Qdrant API key for ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-api-key"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Qdrant-API-Key"
    }
  )
}

resource "aws_secretsmanager_secret_version" "qdrant_api_key" {
  secret_id     = aws_secretsmanager_secret.qdrant_api_key.id
  secret_string = var.qdrant_api_key != "" ? var.qdrant_api_key : random_password.qdrant_api_key.result
}

################################################################################
# Secrets Manager - Qdrant Read-Only API Key
################################################################################

resource "aws_secretsmanager_secret" "qdrant_read_only_key" {
  name                    = "${var.env}/${var.project_id}/${var.base_name}/qdrant-read-only-key"
  description             = "Qdrant read-only API key for ${local.instance_name}"
  recovery_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name        = "${local.instance_name}-read-only-key"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Qdrant-Read-Only-Key"
    }
  )
}

resource "aws_secretsmanager_secret_version" "qdrant_read_only_key" {
  secret_id     = aws_secretsmanager_secret.qdrant_read_only_key.id
  secret_string = var.qdrant_read_only_api_key != "" ? var.qdrant_read_only_api_key : random_password.qdrant_read_only_key.result
}

