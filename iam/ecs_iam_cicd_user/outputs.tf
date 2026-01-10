################################################################################
# ECS IAM CI/CD User Module - Outputs
#
# Purpose: Export user credentials and configuration details for CI/CD setup
################################################################################

output "user" {
  description = "IAM user details"
  value = {
    name = aws_iam_user.cicd.name
    arn  = aws_iam_user.cicd.arn
    id   = aws_iam_user.cicd.unique_id
  }
}

output "user_name" {
  description = "IAM user name"
  value       = aws_iam_user.cicd.name
}

output "user_arn" {
  description = "IAM user ARN"
  value       = aws_iam_user.cicd.arn
}

output "access_key_id" {
  description = "Access key ID for the IAM user (if created)"
  value       = var.create_access_key ? aws_iam_access_key.cicd[0].id : null
  sensitive   = true
}

output "secret_access_key" {
  description = "Secret access key for the IAM user (if created and not encrypted)"
  value       = var.create_access_key && var.pgp_key == null ? aws_iam_access_key.cicd[0].secret : null
  sensitive   = true
}

output "encrypted_secret_access_key" {
  description = "Encrypted secret access key (if PGP key was provided)"
  value       = var.create_access_key && var.pgp_key != null ? aws_iam_access_key.cicd[0].encrypted_secret : null
}

output "credentials" {
  description = <<-EOT
    Complete CI/CD credentials for GitHub Actions or other CI/CD systems.

    ⚠️ SECURITY WARNING:
    - These credentials grant ECS deployment and ECR push permissions
    - Store in CI/CD secrets immediately after reading
    - Delete from terminal history after use
    - Never commit these to version control

    To view: terraform output -json credentials
  EOT
  sensitive = true
  value = var.create_access_key ? {
    access_key_id     = aws_iam_access_key.cicd[0].id
    secret_access_key = var.pgp_key == null ? aws_iam_access_key.cicd[0].secret : null
    encrypted_secret  = var.pgp_key != null ? aws_iam_access_key.cicd[0].encrypted_secret : null
    user_name         = aws_iam_user.cicd.name
    user_arn          = aws_iam_user.cicd.arn
  } : {
    user_name = aws_iam_user.cicd.name
    user_arn  = aws_iam_user.cicd.arn
    message   = "Access key creation is disabled. Set create_access_key = true or use IAM role assumption."
  }
}

output "github_actions_setup_instructions" {
  description = "Instructions for setting up GitHub Actions secrets"
  value       = var.create_access_key ? <<-EOT

    📋 GITHUB ACTIONS SETUP INSTRUCTIONS:

    1. Get credentials (SHOWN ONLY ONCE):
       terraform output -json credentials

    2. Add to GitHub repository secrets:
       Repository → Settings → Secrets and variables → Actions → New secret

       Name: AWS_ACCESS_KEY_ID
       Value: <access_key_id from output>

       Name: AWS_SECRET_ACCESS_KEY
       Value: <secret_access_key from output>

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

output "permissions_summary" {
  description = "Summary of permissions granted to the CI/CD user"
  value = {
    ecr_repositories        = var.ecr_repository_arns
    ecs_permissions_enabled = var.enable_ecs_permissions
    ecs_clusters            = var.ecs_cluster_arns
    ecs_services            = var.ecs_service_arns
    task_definition_prefixes = var.task_definition_family_prefixes
    logs_permissions_enabled = var.enable_cloudwatch_logs_permissions
    log_groups               = var.log_group_arns
  }
}

