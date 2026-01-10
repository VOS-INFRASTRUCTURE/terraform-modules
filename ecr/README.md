# Amazon ECR (Elastic Container Registry) Module

## Overview

This Terraform module creates and manages an Amazon ECR repository for storing Docker container images. It includes automatic lifecycle policies for image cleanup, security scanning, and proper tagging.

## Features

- ✅ **Automatic Image Scanning**: Scan images for vulnerabilities on push
- ✅ **Lifecycle Management**: Automatically delete old images to reduce storage costs
- ✅ **Tag Mutability Control**: Configure whether image tags can be overwritten
- ✅ **Consistent Naming**: Environment and project-based naming convention
- ✅ **Cost Optimization**: Configurable retention policy to prevent unbounded growth
- ✅ **Security Best Practices**: Built-in vulnerability scanning enabled by default

## Usage

### Basic Example

```hcl
module "ecr_node_app" {
  source = "../../ecr"
  
  project_id       = "myapp"
  env              = "staging"
  repo_suffix_name = "ecs-node-app"
}

# Output: Creates repository named "staging-myapp-ecs-node-app"
```

### Production Example with Custom Settings

```hcl
module "ecr_production_api" {
  source = "../../ecr"
  
  project_id       = "platform"
  env              = "production"
  repo_suffix_name = "api-service"
  
  # Prevent tag overwriting in production
  image_tag_mutability = "IMMUTABLE"
  
  # Keep more images in production
  lifecycle_keep_last_count = 30
  
  # Enable security scanning
  scan_on_push = true
}

# Output: Creates repository named "production-platform-api-service"
```

### Multiple Repositories Example

```hcl
# Web Application
module "ecr_web_app" {
  source = "../../ecr"
  
  project_id       = "ecommerce"
  env              = "staging"
  repo_suffix_name = "web-app"
}

# Background Worker
module "ecr_worker" {
  source = "../../ecr"
  
  project_id       = "ecommerce"
  env              = "staging"
  repo_suffix_name = "worker"
}

# API Service
module "ecr_api" {
  source = "../../ecr"
  
  project_id       = "ecommerce"
  env              = "staging"
  repo_suffix_name = "api"
}
```

### Using ECR Repository URL in Task Definitions

```hcl
module "ecr_app" {
  source = "../../ecr"
  
  project_id       = "myapp"
  env              = "staging"
  repo_suffix_name = "node-app"
}

module "ecs_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family        = "staging-app-task"
  container_name     = "app-container"
  
  # Use ECR repository URL from module output
  ecr_repository_url = module.ecr_app.ecr_repository.url
  image_tag          = "v1.0.0"
  
  # ... other configuration
}
```

### Development Environment (Mutable Tags)

```hcl
module "ecr_dev_app" {
  source = "../../ecr"
  
  project_id       = "myapp"
  env              = "development"
  repo_suffix_name = "app"
  
  # Allow tag overwriting in dev
  image_tag_mutability = "MUTABLE"
  
  # Keep fewer images in dev (reduce costs)
  lifecycle_keep_last_count = 5
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| project_id | Project identifier (e.g., 'myapp', 'platform') | `string` | - | yes |
| env | Environment name (e.g., 'staging', 'production', 'development') | `string` | - | yes |
| repo_suffix_name | ECR repository suffix name (e.g., 'ecs-node-app', 'worker', 'api') | `string` | - | yes |
| image_tag_mutability | Tag mutability setting: `MUTABLE` or `IMMUTABLE` | `string` | `"MUTABLE"` | no |
| scan_on_push | Enable automatic image vulnerability scanning on push | `bool` | `true` | no |
| lifecycle_keep_last_count | Number of most recent images to keep (older images auto-deleted) | `number` | `10` | no |

## Outputs

| Name | Description |
|------|-------------|
| ecr_repository | Object containing repository details (name, arn, url) |
| ecr_repository.name | Repository name (e.g., "staging-myapp-ecs-node-app") |
| ecr_repository.arn | Full ARN for IAM policies and resource references |
| ecr_repository.url | Full registry URL for docker push/pull commands |

### Output Usage Examples

```hcl
# Reference the repository URL
output "image_url" {
  value = "${module.ecr_app.ecr_repository.url}:latest"
}

# Use in IAM policy
data "aws_iam_policy_document" "ecr_access" {
  statement {
    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [module.ecr_app.ecr_repository.arn]
  }
}

# Print repository name
output "repo_name" {
  value = module.ecr_app.ecr_repository.name
}
```

## Repository Naming Convention

The module creates repositories with the following naming pattern:

```
{env}-{project_id}-{repo_suffix_name}
```

### Examples:

- `staging-myapp-ecs-node-app`
- `production-platform-api-service`
- `development-ecommerce-web-app`

## Lifecycle Policy

### How It Works

The module automatically configures a lifecycle policy to prevent unbounded repository growth and reduce storage costs.

**Strategy:**
- Keep the latest N images (based on push time)
- Automatically delete older images

**Example with `lifecycle_keep_last_count = 10`:**

```
Repository images (oldest to newest):
v1, v2, v3, v4, v5, v6, v7, v8, v9, v10, v11, v12, v13, v14, v15

Policy keeps:    v6, v7, v8, v9, v10, v11, v12, v13, v14, v15 (latest 10)
Policy deletes:  v1, v2, v3, v4, v5 (older than latest 10)
```

### Recommended Settings by Environment

| Environment | Recommended Count | Reason |
|-------------|-------------------|--------|
| Development | 5 | Fast iteration, cost savings |
| Staging | 10-15 | Balance between testing and cost |
| Production | 20-30 | More rollback options, audit trail |

## Image Tag Mutability

### MUTABLE (Default)

- Tags can be overwritten
- Same tag can point to different images over time
- Example: You can push multiple images with tag `latest`

**Use Cases:**
- Development environments
- Staging environments
- When using `latest` or environment-based tags

**Example:**
```bash
# First push
docker tag myapp:v1 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-app:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-app:latest

# Later push (overwrites the previous image)
docker tag myapp:v2 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-app:latest
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-app:latest
```

### IMMUTABLE

- Tags cannot be overwritten
- Each tag must be unique
- Attempting to push an existing tag will fail

**Use Cases:**
- Production environments
- Compliance requirements
- When using semantic versioning or commit SHAs

**Example:**
```bash
# First push - succeeds
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/prod-myapp-app:v1.0.0

# Attempt to push same tag - FAILS
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/prod-myapp-app:v1.0.0
# Error: tag already exists

# Must use different tag - succeeds
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/prod-myapp-app:v1.0.1
```

## Image Scanning

The module enables automatic vulnerability scanning by default (`scan_on_push = true`).

### What Gets Scanned

- Operating system vulnerabilities
- Known CVEs (Common Vulnerabilities and Exposures)
- Package vulnerabilities in common package managers

### Viewing Scan Results

```bash
# View scan results via AWS CLI
aws ecr describe-image-scan-findings \
  --repository-name staging-myapp-ecs-node-app \
  --image-id imageTag=v1.0.0

# View in AWS Console
# Navigate to: ECR → Repositories → [Your Repo] → Images → [Select Image] → Scan Results
```

### Recommended Actions

1. **Critical/High Vulnerabilities**: Fix immediately before deployment
2. **Medium Vulnerabilities**: Plan fixes in upcoming sprints
3. **Low/Informational**: Review and prioritize based on risk

## Working with ECR

### Authenticate Docker with ECR

```bash
# Get login password and authenticate
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
```

### Build and Push Image

```bash
# Build your Docker image
docker build -t myapp:v1.0.0 .

# Tag for ECR
docker tag myapp:v1.0.0 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-ecs-node-app:v1.0.0

# Push to ECR
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-ecs-node-app:v1.0.0
```

### Pull Image from ECR

```bash
# Authenticate first (if not already authenticated)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Pull image
docker pull 123456789.dkr.ecr.us-east-1.amazonaws.com/staging-myapp-ecs-node-app:v1.0.0
```

### List Images in Repository

```bash
# List all images
aws ecr list-images --repository-name staging-myapp-ecs-node-app

# List with details
aws ecr describe-images --repository-name staging-myapp-ecs-node-app
```

### Delete Specific Image

```bash
# Delete by tag
aws ecr batch-delete-image \
  --repository-name staging-myapp-ecs-node-app \
  --image-ids imageTag=v1.0.0
```

## Cost Optimization

### ECR Pricing (as of 2026)

- **Storage**: $0.10 per GB per month
- **Data Transfer OUT**: $0.09 per GB (to internet)
- **Data Transfer**: Free within same region (ECR → ECS)

### Cost Calculation Examples

**Example 1: Small Application**
- 10 images at 500 MB each = 5 GB
- Monthly cost: 5 GB × $0.10 = **$0.50/month**

**Example 2: Without Lifecycle Policy**
- Unlimited image accumulation over 6 months
- 100 images at 500 MB each = 50 GB
- Monthly cost: 50 GB × $0.10 = **$5.00/month**

**Example 3: With Lifecycle Policy (keep last 10)**
- Always maintains only 10 images
- 10 images at 500 MB each = 5 GB
- Monthly cost: 5 GB × $0.10 = **$0.50/month**
- **Savings: $4.50/month** ✅

### Cost-Saving Tips

1. **Use Lifecycle Policies**: Keep only necessary images
2. **Optimize Image Size**: Use multi-stage builds, alpine base images
3. **Delete Unused Repositories**: Clean up old/deprecated repos
4. **Monitor Storage**: Set CloudWatch alarms for unexpected growth

## Security Best Practices

1. **Enable Scan on Push**: Catch vulnerabilities early (`scan_on_push = true`)
2. **Use IMMUTABLE Tags in Production**: Prevent accidental overwrites
3. **Use Least Privilege IAM**: Grant only necessary ECR permissions
4. **Use Specific Tags**: Avoid `latest` in production (use commit SHAs or versions)
5. **Encrypt at Rest**: ECR encrypts images by default with AES-256
6. **Enable CloudTrail**: Audit all ECR API calls
7. **Use VPC Endpoints**: Keep traffic within AWS network (optional)

## Troubleshooting

### "denied: User is not authorized" Error

**Problem**: Cannot push/pull images

**Solution**:
```bash
# Re-authenticate with ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com
```

### "tag already exists" Error (IMMUTABLE repositories)

**Problem**: Cannot push with existing tag

**Solution**:
```bash
# Use a new, unique tag
docker tag myapp:latest 123456789.dkr.ecr.us-east-1.amazonaws.com/prod-app:v1.0.1
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/prod-app:v1.0.1
```

### Repository Not Found

**Problem**: `docker push` fails with "repository does not exist"

**Solution**:
```bash
# Verify repository exists
aws ecr describe-repositories --repository-names staging-myapp-ecs-node-app

# If not exists, apply Terraform
terraform apply
```

### Images Being Deleted Unexpectedly

**Problem**: Recent images are being deleted

**Solution**:
- Check `lifecycle_keep_last_count` setting
- Increase the count if you need more images retained
- Images are deleted only when count exceeds the limit

## Integration with CI/CD

### GitHub Actions Example

```yaml
name: Build and Push to ECR

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1
      
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
      
      - name: Build, tag, and push image
        env:
          ECR_REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          ECR_REPOSITORY: staging-myapp-ecs-node-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG
```

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0
- AWS credentials with ECR permissions:
  - `ecr:CreateRepository`
  - `ecr:PutLifecyclePolicy`
  - `ecr:PutImageScanningConfiguration`
  - `ecr:DescribeRepositories`

## Related Modules

- [ECS Task Definition (Node.js)](../ecs/task_definitions/node_js/basic_node_js_task_definition/) - Use ECR images in ECS tasks
- [ECS Task Execution Role](../ecs/ecs_task_execution_role/) - Required for ECS to pull images from ECR
- [ECS Task Role](../ecs/ecs_task_role/) - Runtime permissions for ECS tasks

## Examples

See the [USAGE_EXAMPLES.md](./USAGE_EXAMPLES.md) file for more detailed examples and use cases.

## License

MIT

## Author

Created as part of the VOS Terraform Modules library.

## Support

For issues, questions, or contributions, please refer to the main repository documentation.

