################################################################################
# Secrets Manager - Qdrant API Keys
#
# Purpose: Store Qdrant API key securely in AWS Secrets Manager
# Security: Key is never stored in plain text or in Terraform state
#
# Note: Qdrant uses a single API key for authentication. For read-only access,
#       you should configure collection-level permissions via the Qdrant API
#       after deployment, not via environment variables.
################################################################################

################################################################################
# Random Password Generation (if not provided)
################################################################################

resource "random_password" "qdrant_api_key" {
  length  = 32
  special = true
}

################################################################################
# Secrets Manager - Qdrant API Key
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


