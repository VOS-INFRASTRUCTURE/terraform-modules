# ECS IAM CI/CD User Module

## Overview

This Terraform module creates a dedicated IAM user with least-privilege permissions for deploying to Amazon ECS via CI/CD pipelines (GitHub Actions, GitLab CI, Jenkins, etc.). The user has only the minimal permissions needed for ECS deployments and ECR image management.

## Security Model

- ✅ **Separate from Terraform credentials**: CI/CD user cannot modify infrastructure
- ✅ **Least-privilege**: Only ECS deploy + ECR push permissions
- ✅ **No infrastructure modification**: Cannot create/delete resources
- ✅ **Scoped to specific resources**: Limited to specific services and repositories
- ✅ **Auditable**: All actions logged via CloudTrail

## Features

- ✅ **ECR Permissions**: Push/pull Docker images to specified repositories
- ✅ **ECS Deployment**: Register task definitions and update services
- ✅ **CloudWatch Logs**: Read-only access to application logs (optional)
- ✅ **IAM PassRole**: Limited to specific task execution/task roles
- ✅ **Flexible Configuration**: Enable/disable features as needed
- ✅ **PGP Encryption**: Optional encryption of secret access key
- ✅ **GitHub Actions Ready**: Includes setup instructions

## Usage

### Basic Example (Single Service)

```hcl
module "github_actions_cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  
  user_name = "staging-node-app-github-actions"
  
  # ECR Repository Access
  ecr_repository_arns = [
    module.ecr_app.ecr_repository.arn
  ]
  
  # ECS Deployment Access
  ecs_service_arns = [
    aws_ecs_service.node_app_service.id
  ]
  
  task_definition_family_prefixes = [
    "staging-ecs-node-app"
  ]
  
  task_execution_role_arns = [
    module.ecs_task_execution_role.role.arn
  ]
  
  task_role_arns = [
    module.ecs_task_role.role.arn
  ]
  
  # CloudWatch Logs Access
  log_group_arns = [
    aws_cloudwatch_log_group.app_logs.arn
  ]
  
  # Tagging
  environment = "staging"
  project_id  = "node-app"
}

# Output the complete CI/CD configuration
output "cicd_user" {
  value     = module.github_actions_cicd_user.cicd
  sensitive = true
}
```

### Multiple Services Example

```hcl
module "cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  
  user_name = "production-platform-github-actions"
  
  # Multiple ECR repositories
  ecr_repository_arns = [
    module.ecr_web_app.ecr_repository.arn,
    module.ecr_api.ecr_repository.arn,
    module.ecr_worker.ecr_repository.arn
  ]
  
  # Multiple ECS services
  ecs_service_arns = [
    aws_ecs_service.web_app.id,
    aws_ecs_service.api.id,
    aws_ecs_service.worker.id
  ]
  
  task_definition_family_prefixes = [
    "production-web-app",
    "production-api",
    "production-worker"
  ]
  
  # Multiple roles
  task_execution_role_arns = [
    module.ecs_task_execution_role.role.arn
  ]
  
  task_role_arns = [
    module.web_task_role.role.arn,
    module.api_task_role.role.arn,
    module.worker_task_role.role.arn
  ]
  
  # Multiple log groups
  log_group_arns = [
    aws_cloudwatch_log_group.web_logs.arn,
    aws_cloudwatch_log_group.api_logs.arn,
    aws_cloudwatch_log_group.worker_logs.arn
  ]
  
  environment = "production"
  project_id  = "platform"
}
```

### ECR-Only User (No ECS Permissions)

```hcl
module "ecr_only_cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  
  user_name = "docker-build-user"
  
  # Only ECR access
  ecr_repository_arns = [
    module.ecr_app.ecr_repository.arn
  ]
  
  # Disable ECS permissions
  enable_ecs_permissions = false
  
  # Disable CloudWatch Logs
  enable_cloudwatch_logs_permissions = false
  
  environment = "ci"
}
```

### With PGP Encryption

```hcl
module "cicd_user_encrypted" {
  source = "../../iam/ecs_iam_cicd_user"
  
  user_name = "production-cicd-user"
  
  ecr_repository_arns = [module.ecr_app.ecr_repository.arn]
  ecs_service_arns    = [aws_ecs_service.app.id]
  
  task_definition_family_prefixes = ["production-app"]
  task_execution_role_arns        = [module.execution_role.role.arn]
  task_role_arns                  = [module.task_role.role.arn]
  
  # Encrypt secret key with PGP
  pgp_key = "keybase:username"  # or base64-encoded PGP public key
  
  environment = "production"
}

# Decrypt with: terraform output -raw encrypted_secret | base64 -d | gpg -d
```

### Without Access Key (For IAM Role Assumption)

```hcl
module "cicd_user_no_keys" {
  source = "../../iam/ecs_iam_cicd_user"
  
  user_name = "staging-cicd-user"
  
  ecr_repository_arns          = [module.ecr_app.ecr_repository.arn]
  ecs_service_arns             = [aws_ecs_service.app.id]
  task_definition_family_prefixes = ["staging-app"]
  task_execution_role_arns     = [module.execution_role.role.arn]
  task_role_arns               = [module.task_role.role.arn]
  
  # Don't create access key (use assume role instead)
  create_access_key = false
  
  environment = "staging"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| user_name | Name for the IAM CI/CD user | `string` | - | yes |
| ecr_repository_arns | List of ECR repository ARNs for push/pull access | `list(string)` | - | yes |
| enable_ecs_permissions | Whether to grant ECS deployment permissions | `bool` | `true` | no |
| ecs_cluster_arns | List of ECS cluster ARNs (informational) | `list(string)` | `[]` | no |
| ecs_service_arns | List of ECS service ARNs that can be updated | `list(string)` | `[]` | no |
| task_definition_family_prefixes | List of task definition family name prefixes | `list(string)` | `[]` | no |
| task_execution_role_arns | List of task execution role ARNs for PassRole | `list(string)` | `[]` | no |
| task_role_arns | List of task role ARNs for PassRole | `list(string)` | `[]` | no |
| enable_cloudwatch_logs_permissions | Whether to grant CloudWatch Logs read access | `bool` | `true` | no |
| log_group_arns | List of CloudWatch Log Group ARNs for read access | `list(string)` | `[]` | no |
| create_access_key | Whether to create an access key | `bool` | `true` | no |
| pgp_key | Optional PGP key to encrypt secret access key | `string` | `null` | no |
| tags | Additional tags for the IAM user | `map(string)` | `{}` | no |
| environment | Environment name (added to tags) | `string` | `""` | no |
| project_id | Project identifier (added to tags) | `string` | `""` | no |
| additional_policy_arns | Additional IAM policy ARNs to attach | `list(string)` | `[]` | no |
| policy_name_prefix | Prefix for inline policy names | `string` | `"cicd"` | no |
| aws_region | AWS region for ARN construction | `string` | `""` | no |
| aws_account_id | AWS account ID for ARN construction | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| cicd | Complete CI/CD configuration object (user, credentials, permissions) |
| cicd.user | IAM user details (name, arn, id) |
| cicd.credentials | Access credentials (access_key_id, secret_access_key, encrypted_secret) |
| cicd.permissions | Permissions summary (ECR repos, ECS services, log groups, etc.) |

### Output Structure

```hcl
output "cicd" {
  value = {
    user = {
      name = "..."  # IAM user name
      arn  = "..."  # IAM user ARN
      id   = "..."  # Unique user ID
    }
    
    credentials = {
      access_key_id     = "..."  # AWS Access Key ID
      secret_access_key = "..."  # Secret Access Key (plaintext or null)
      encrypted_secret  = "..."  # Secret Access Key (PGP encrypted or null)
    }
    
    permissions = {
      ecr_repositories         = [...]  # ECR repository ARNs
      ecs_permissions_enabled  = true   # Whether ECS is enabled
      ecs_clusters             = [...]  # ECS cluster ARNs
      ecs_services             = [...]  # ECS service ARNs
      task_definition_prefixes = [...]  # Task definition family prefixes
      logs_permissions_enabled = true   # Whether CloudWatch Logs is enabled
      log_groups               = [...]  # Log group ARNs
    }
  }
  sensitive = true
}
```

### Usage Examples

```bash
# View complete output
terraform output -json cicd

# Get user name
terraform output -json cicd | jq -r '.user.name'

# Get credentials
terraform output -json cicd | jq -r '.credentials.access_key_id'
terraform output -json cicd | jq -r '.credentials.secret_access_key'

# View permissions
terraform output -json cicd | jq -r '.permissions'
```

## Permissions Granted

### 1. ECR Permissions (Always Enabled)

- `ecr:GetAuthorizationToken` - Login to ECR
- `ecr:BatchCheckLayerAvailability` - Check image layers
- `ecr:GetDownloadUrlForLayer` - Pull images
- `ecr:BatchGetImage` - Pull images
- `ecr:PutImage` - Push images
- `ecr:InitiateLayerUpload` - Upload image layers
- `ecr:UploadLayerPart` - Upload image layers
- `ecr:CompleteLayerUpload` - Complete image upload
- `ecr:DescribeRepositories` - List repositories
- `ecr:ListImages` - List images
- `ecr:DescribeImages` - Describe images

**Scope**: Limited to specified ECR repositories only

### 2. ECS Permissions (Optional - enabled by default)

- `ecs:DescribeTaskDefinition` - View task definitions
- `ecs:DescribeServices` - View services
- `ecs:DescribeTasks` - View running tasks
- `ecs:ListTasks` - List tasks
- `ecs:DescribeClusters` - View clusters
- `ecs:ListTaskDefinitions` - List task definitions
- `ecs:RegisterTaskDefinition` - Create new task definition revisions
- `ecs:DeregisterTaskDefinition` - Remove old task definitions
- `ecs:UpdateService` - Deploy new task definitions
- `ecs:RunTask` - Run one-off tasks
- `ecs:StopTask` - Stop tasks

**Scope**: Limited to specified services and task definition families

### 3. IAM PassRole Permissions (Optional - enabled with ECS)

- `iam:PassRole` - Pass roles to ECS tasks

**Scope**: 
- Limited to specified task execution and task roles only
- Only when passing to `ecs-tasks.amazonaws.com`

### 4. CloudWatch Logs Permissions (Optional - enabled by default)

- `logs:GetLogEvents` - Read log events
- `logs:FilterLogEvents` - Filter logs
- `logs:DescribeLogStreams` - List log streams
- `logs:DescribeLogGroups` - List log groups

**Scope**: Limited to specified log groups only

## Setting Up GitHub Actions

### Step 1: Retrieve Credentials

```bash
# View complete output
terraform output -json cicd

# Extract specific values
terraform output -json cicd | jq -r '.credentials.access_key_id'
terraform output -json cicd | jq -r '.credentials.secret_access_key'
```

### Step 2: Add to GitHub Secrets

1. Navigate to your GitHub repository
2. Go to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add two secrets:
   - `AWS_ACCESS_KEY_ID`: The access key ID
   - `AWS_SECRET_ACCESS_KEY`: The secret access key

### Step 3: Use in GitHub Actions Workflow

```yaml
name: Deploy to ECS

on:
  push:
    branches: [main, staging]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build, tag, and push Docker image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: staging-myapp-ecs-node-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
      
      - name: Update ECS service
        env:
          CLUSTER_NAME: staging-ecs-cluster
          SERVICE_NAME: staging-node-app-service
        run: |
          aws ecs update-service \
            --cluster $CLUSTER_NAME \
            --service $SERVICE_NAME \
            --force-new-deployment
```

## Security Best Practices

### 1. Rotate Access Keys Regularly

```bash
# Create new access key
terraform apply

# Update GitHub Secrets with new credentials

# Delete old access key via AWS Console
```

### 2. Use PGP Encryption in Production

```hcl
module "cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  
  # ...
  
  pgp_key = "keybase:yourname"
}
```

### 3. Monitor Usage with CloudTrail

Enable CloudTrail to audit all actions performed by the CI/CD user.

### 4. Use Separate Users Per Environment

```hcl
# Staging
module "staging_cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  user_name = "staging-cicd-user"
  # ... staging resources ...
}

# Production
module "production_cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"
  user_name = "production-cicd-user"
  # ... production resources ...
}
```

### 5. Limit to Specific Services

Never use `"*"` for service ARNs. Always specify exact services:

```hcl
# ❌ BAD
ecs_service_arns = ["*"]

# ✅ GOOD
ecs_service_arns = [
  aws_ecs_service.app.id,
  aws_ecs_service.worker.id
]
```

## Troubleshooting

### "Access Denied" Errors

**Problem**: CI/CD pipeline fails with permission errors

**Solutions**:

1. **Check ECR repository ARN**:
   ```bash
   aws ecr describe-repositories --repository-names your-repo-name
   ```

2. **Verify service ARN**:
   ```bash
   aws ecs describe-services --cluster your-cluster --services your-service
   ```

3. **Test permissions locally**:
   ```bash
   export AWS_ACCESS_KEY_ID="..."
   export AWS_SECRET_ACCESS_KEY="..."
   aws ecs describe-services --cluster your-cluster --services your-service
   ```

### "User Already Exists" Error

**Problem**: User name conflicts with existing user

**Solution**: Change `user_name` variable to a unique value

### Cannot PassRole to ECS

**Problem**: `iam:PassRole` permission denied

**Solution**: Ensure `task_execution_role_arns` and `task_role_arns` include all roles referenced in your task definition

## GitLab CI/CD Example

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  image: amazon/aws-cli:latest
  variables:
    AWS_DEFAULT_REGION: us-east-1
  script:
    - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
    - docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$CI_COMMIT_SHA .
    - docker push $ECR_REGISTRY/$ECR_REPOSITORY:$CI_COMMIT_SHA
    - aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --force-new-deployment
  only:
    - main
```

Set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` in GitLab CI/CD variables.

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0
- Existing ECS resources (clusters, services, task definitions)
- Existing ECR repositories
- Existing IAM roles (task execution role, task role)

## Related Modules

- [ECR](../../ecr/) - Create ECR repositories
- [ECS Task Execution Role](../../ecs/ecs_task_execution_role/) - ECS task execution role
- [ECS Task Role](../../ecs/ecs_task_role/) - ECS task runtime role
- [ECS Task Definition](../../ecs/task_definitions/node_js/basic_node_js_task_definition/) - Task definitions

## License

MIT

## Author

Created as part of the VOS Terraform Modules library.

## Support

For issues, questions, or contributions, please refer to the main repository documentation.

