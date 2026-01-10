################################################################################
# ECS IAM CI/CD User Module - Outputs
#
# Purpose: Export user credentials and configuration details for CI/CD setup
#
# Usage:
#   module.cicd_user.cicd.user.name
#   module.cicd_user.cicd.credentials.access_key_id
#   module.cicd_user.cicd.permissions.ecr_repositories
#
# ⚠️ SECURITY WARNING:
# The credentials output is sensitive. Store in CI/CD secrets immediately.
# Never commit credentials to version control.
################################################################################

output "cicd" {
  description = "Complete CI/CD user configuration, credentials, and permissions"
  sensitive   = true

  value = {
    # IAM User Details
    user = {
      name = aws_iam_user.cicd.name                                        # IAM user name
      arn  = aws_iam_user.cicd.arn                                         # Full ARN for IAM policies
      id   = aws_iam_user.cicd.unique_id                                   # Unique user ID
    }

    # Access Credentials (⚠️ SENSITIVE - Store in CI/CD secrets immediately!)
    credentials = var.create_access_key ? {
      access_key_id     = aws_iam_access_key.cicd[0].id                   # AWS Access Key ID
      secret_access_key = var.pgp_key == null ? aws_iam_access_key.cicd[0].secret : null  # Secret Key (plaintext)
      encrypted_secret  = var.pgp_key != null ? aws_iam_access_key.cicd[0].encrypted_secret : null  # Secret Key (PGP encrypted)
    } : {
      message = "Access key creation disabled. Set create_access_key = true to generate credentials."
    }

    # Permissions Summary
    permissions = {
      ecr_repositories         = var.ecr_repository_arns                  # ECR repos with push/pull access
      ecs_permissions_enabled  = var.enable_ecs_permissions               # Whether ECS deployment is enabled
      ecs_clusters             = var.ecs_cluster_arns                     # ECS clusters (informational)
      ecs_services             = var.ecs_service_arns                     # ECS services that can be updated
      task_definition_prefixes = var.task_definition_family_prefixes      # Task definition families
      logs_permissions_enabled = var.enable_cloudwatch_logs_permissions   # Whether CloudWatch Logs access is enabled
      log_groups               = var.log_group_arns                       # Log groups with read access
    }
  }
}
