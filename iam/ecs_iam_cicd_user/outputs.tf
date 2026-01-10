################################################################################
# ECS IAM CI/CD User Module - Outputs
#
# Purpose: Export user credentials and configuration details for CI/CD setup
#
# Usage:
#   module.cicd_user.cicd.user.name
#   module.cicd_user.cicd.credentials.access_key_id
#   module.cicd_user.cicd.permissions.ecr_repositories
################################################################################

output "cicd" {
  description = "Complete CI/CD user configuration, credentials, and setup instructions"
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

      # Security Warning
      warning = <<-EOT
        ⚠️ SECURITY WARNING:
        - These credentials grant ECS deployment and ECR push permissions
        - Store in CI/CD secrets immediately after reading
        - Delete from terminal history: history -c
        - Never commit these to version control

        To view: terraform output -json cicd
      EOT
    } : {
      message = "Access key creation is disabled. Set create_access_key = true or use IAM role assumption."
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

    # GitHub Actions Setup Instructions
    github_actions_setup = var.create_access_key ? <<-EOT

      📋 GITHUB ACTIONS SETUP INSTRUCTIONS:

      1. Get credentials (SHOWN ONLY ONCE):
         terraform output -json cicd | jq -r '.credentials'

      2. Add to GitHub repository secrets:
         Repository → Settings → Secrets and variables → Actions → New secret

         Name: AWS_ACCESS_KEY_ID
         Value: ${var.create_access_key ? "<access_key_id from output>" : "N/A"}

         Name: AWS_SECRET_ACCESS_KEY
         Value: ${var.create_access_key ? "<secret_access_key from output>" : "N/A"}

      3. Clear credentials from terminal:
         history -c

      4. Test deployment:
         Push to your branch and check the Actions tab

      ✅ The CI/CD user has least-privilege permissions:
         - ECR: Push/pull to specified repositories only
         - ECS: Update specified services only
         - Logs: Read specified log groups only
         - NO infrastructure modification permissions

      📖 Example GitHub Actions workflow:

      ```yaml
      name: Deploy to ECS
      on:
        push:
          branches: [main]

      jobs:
        deploy:
          runs-on: ubuntu-latest
          steps:
            - uses: actions/checkout@v3

            - name: Configure AWS credentials
              uses: aws-actions/configure-aws-credentials@v2
              with:
                aws-access-key-id: $${{ secrets.AWS_ACCESS_KEY_ID }}
                aws-secret-access-key: $${{ secrets.AWS_SECRET_ACCESS_KEY }}
                aws-region: ${local.region}

            - name: Login to Amazon ECR
              id: login-ecr
              uses: aws-actions/amazon-ecr-login@v1

            - name: Build and push Docker image
              env:
                ECR_REGISTRY: $${{ steps.login-ecr.outputs.registry }}
                IMAGE_TAG: $${{ github.sha }}
              run: |
                docker build -t $$ECR_REGISTRY/YOUR_REPO:$$IMAGE_TAG .
                docker push $$ECR_REGISTRY/YOUR_REPO:$$IMAGE_TAG

            - name: Deploy to ECS
              run: |
                aws ecs update-service \
                  --cluster YOUR_CLUSTER \
                  --service YOUR_SERVICE \
                  --force-new-deployment
      ```
    EOT
    : "Access key creation is disabled. Enable it with create_access_key = true for setup instructions."
  }

  sensitive = true  # Mark entire output as sensitive to protect credentials
}
