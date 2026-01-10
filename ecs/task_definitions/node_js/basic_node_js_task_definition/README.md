# Basic Node.js ECS Task Definition Module

## Overview

This Terraform module creates a reusable ECS Task Definition for Node.js applications running on AWS Fargate. It abstracts the complexity of task definition configuration and provides a clean interface for deploying Node.js containerized applications with proper logging, health checks, and CI/CD compatibility.

## Features

- ✅ **Fargate-Compatible**: Runs on AWS Fargate (serverless container platform)
- ✅ **CloudWatch Logging**: Automatic log aggregation with configurable retention
- ✅ **Health Checks**: Built-in HTTP health check support for Node.js apps
- ✅ **Secrets Management**: Seamless integration with SSM Parameter Store and Secrets Manager
- ✅ **CI/CD Ready**: Lifecycle management to prevent Terraform from reverting CI/CD image updates
- ✅ **Flexible Configuration**: Adjustable CPU, memory, environment variables, and more
- ✅ **Production-Ready**: Includes best practices and comprehensive documentation

## Usage

### Basic Example

```hcl
module "node_app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"

  # Task Configuration
  task_family            = "staging-node-app-task"
  container_name         = "node-app-container"
  
  # Container Image
  ecr_repository_url     = module.ecr_repo.ecr_repository.url
  image_tag              = "0342c14a991591e22f707fe924a87b677a4a915d"
  
  # IAM Roles
  execution_role_arn     = module.ecs_task_execution_role.role.arn
  task_role_arn          = module.ecs_task_role.role.arn
  
  # AWS Configuration
  region                 = "us-east-1"
  
  # Logging
  log_group_name         = "/ecs/staging-node-app"
  log_retention_days     = 30
  
  # Tagging
  environment            = "staging"
  project_id             = "my-project"
  
  tags = {
    Team = "DevOps"
  }
}
```

### Example with Secrets from SSM Parameter Store

```hcl
# Create SSM parameters first
resource "aws_ssm_parameter" "app_port" {
  name  = "/staging/node-app/PORT"
  type  = "String"
  value = "3000"
}

resource "aws_ssm_parameter" "node_env" {
  name  = "/staging/node-app/NODE_ENV"
  type  = "String"
  value = "production"
}

# Use in task definition
module "node_app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"

  task_family            = "staging-node-app-task"
  container_name         = "node-app-container"
  ecr_repository_url     = module.ecr_repo.ecr_repository.url
  image_tag              = var.app_image_tag
  execution_role_arn     = module.ecs_task_execution_role.role.arn
  task_role_arn          = module.ecs_task_role.role.arn
  region                 = "us-east-1"
  log_group_name         = "/ecs/staging-node-app"

  # Inject secrets from SSM
  secrets = [
    {
      name      = "PORT"
      valueFrom = aws_ssm_parameter.app_port.arn
    },
    {
      name      = "NODE_ENV"
      valueFrom = aws_ssm_parameter.node_env.arn
    }
  ]

  # Static environment variables
  environment_variables = [
    {
      name  = "CONTAINER_MODE"
      value = "app"
    }
  ]
}
```

### Example with Custom Resource Allocation

```hcl
module "node_app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"

  task_family            = "production-node-app-task"
  container_name         = "node-app-container"
  ecr_repository_url     = module.ecr_repo.ecr_repository.url
  image_tag              = var.app_image_tag
  execution_role_arn     = module.ecs_task_execution_role.role.arn
  task_role_arn          = module.ecs_task_role.role.arn
  region                 = "us-east-1"
  log_group_name         = "/ecs/production-node-app"

  # Increased resources for production
  cpu                    = "1024"   # 1 vCPU
  memory                 = "2048"   # 2 GB RAM

  # Custom health check
  health_check_endpoint  = "/api/health"
  health_check_interval  = 15
  health_check_timeout   = 10
  health_check_retries   = 5
  health_check_start_period = 120

  environment            = "production"
  project_id             = "critical-app"
}
```

### Example with Custom Port

```hcl
module "node_app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"

  task_family            = "api-task"
  container_name         = "api-container"
  ecr_repository_url     = module.ecr_repo.ecr_repository.url
  image_tag              = "v1.2.3"
  execution_role_arn     = module.ecs_task_execution_role.role.arn
  task_role_arn          = module.ecs_task_role.role.arn
  region                 = "eu-west-1"
  log_group_name         = "/ecs/api-service"

  # Custom port
  container_port         = 8080

  environment            = "staging"
}
```

### Example Without Lifecycle Ignore Changes (Terraform Manages Everything)

```hcl
module "node_app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"

  task_family            = "managed-task"
  container_name         = "managed-container"
  ecr_repository_url     = module.ecr_repo.ecr_repository.url
  image_tag              = var.controlled_image_tag
  execution_role_arn     = module.ecs_task_execution_role.role.arn
  task_role_arn          = module.ecs_task_role.role.arn
  region                 = "us-east-1"
  log_group_name         = "/ecs/managed-app"

  # Allow Terraform to manage container definitions
  ignore_changes_to_container_definitions = false

  environment            = "development"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| task_family | Name/family for the ECS task definition | `string` | - | yes |
| container_name | Name for the container within the task definition | `string` | - | yes |
| ecr_repository_url | URL of the ECR repository containing the Docker image | `string` | - | yes |
| image_tag | Docker image tag (use commit SHA, version, or build number) | `string` | - | yes |
| execution_role_arn | ARN of the ECS task execution role | `string` | - | yes |
| task_role_arn | ARN of the ECS task role | `string` | - | yes |
| region | AWS region for CloudWatch logs | `string` | - | yes |
| container_port | Port that the container exposes | `number` | `3000` | no |
| container_protocol | Protocol for the container port | `string` | `"tcp"` | no |
| cpu | CPU allocation in CPU units (256, 512, 1024, 2048, 4096) | `string` | `"256"` | no |
| memory | Memory allocation in MiB (512-30720 depending on CPU) | `string` | `"1024"` | no |
| secrets | List of secrets from SSM/Secrets Manager | `list(object)` | `[]` | no |
| environment_variables | List of static environment variables | `list(object)` | `[]` | no |
| log_group_name | Name for the CloudWatch log group | `string` | - | yes |
| create_log_group | Whether to create a CloudWatch log group | `bool` | `true` | no |
| log_retention_days | Number of days to retain logs | `number` | `30` | no |
| log_stream_prefix | Prefix for CloudWatch log streams | `string` | `"ecs"` | no |
| health_check_enabled | Whether to enable container health checks | `bool` | `true` | no |
| health_check_endpoint | HTTP endpoint path for health checks | `string` | `"/health"` | no |
| health_check_interval | Time between health checks (seconds) | `number` | `30` | no |
| health_check_timeout | Time to wait for health check response (seconds) | `number` | `5` | no |
| health_check_retries | Number of consecutive failures before unhealthy | `number` | `3` | no |
| health_check_start_period | Grace period for container startup (seconds) | `number` | `60` | no |
| ignore_changes_to_container_definitions | Ignore changes to container_definitions (for CI/CD) | `bool` | `true` | no |
| tags | Additional tags to apply to resources | `map(string)` | `{}` | no |
| environment | Environment name (added to default tags) | `string` | `""` | no |
| project_id | Project identifier (added to default tags) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| task_definition | Complete ECS Task Definition details (arn, family, revision) |
| task_definition_arn | ARN of the ECS task definition (without revision) |
| task_definition_family | Family name of the ECS task definition |
| task_definition_revision | Revision number of the ECS task definition |
| log_group | CloudWatch Log Group details (if created) |
| log_group_name | Name of the CloudWatch Log Group |
| container_name | Name of the container defined in the task definition |
| container_port | Port that the container exposes |
| container_image | Full container image URL with tag |
| cpu | CPU units allocated to the task |
| memory | Memory (MiB) allocated to the task |

## CPU and Memory Combinations

Valid CPU and memory combinations for Fargate:

| CPU (units) | vCPU | Memory (MiB) | Memory (GB) | Cost/Hour (EU-West-2) | Cost/Month |
|-------------|------|--------------|-------------|----------------------|------------|
| 256 | 0.25 | 512-2048 | 0.5-2 GB | $0.01675 | ~$12.23 |
| 512 | 0.5 | 1024-4096 | 1-4 GB | $0.02698 | ~$19.69 |
| 1024 | 1 | 2048-8192 | 2-8 GB | $0.04656 | ~$33.99 |
| 2048 | 2 | 4096-16384 | 4-16 GB | $0.09312 | ~$67.98 |
| 4096 | 4 | 8192-30720 | 8-30 GB | $0.18624 | ~$135.96 |

*Pricing shown for 0.25 vCPU + 1 GB memory configuration*

## Container Restart & Configuration Updates

### ⚠️ Important: Secrets Are Injected Only at Container Startup

When you update SSM parameters or Secrets Manager values, **existing containers DO NOT automatically get the new values**. You must force a restart.

### Method 1: Re-run GitHub Actions Workflow (RECOMMENDED) ⭐

**Easiest and most reliable method:**

1. Go to GitHub → Actions tab
2. Find the last successful workflow run
3. Click "Re-run all jobs"

**What happens:**
- GitHub Actions builds a new Docker image
- Pushes new image to ECR with new tag (commit SHA)
- Updates ECS task definition with new image tag
- ECS starts rolling deployment
- New tasks fetch **LATEST** values from SSM/Secrets Manager
- ALB routes traffic to new tasks once healthy
- Old tasks are drained and stopped
- **Zero downtime!** ✅

**Time:** 3-7 minutes (includes build + deployment)  
**Downtime:** NONE

### Method 2: Force New Deployment via AWS CLI

```bash
aws ecs update-service \
  --cluster YOUR-CLUSTER-NAME \
  --service YOUR-SERVICE-NAME \
  --force-new-deployment
```

**Time:** 2-5 minutes  
**Downtime:** NONE

### Method 3: Stop Individual Tasks

```bash
# List running tasks
aws ecs list-tasks \
  --cluster YOUR-CLUSTER-NAME \
  --service-name YOUR-SERVICE-NAME

# Stop a task (ECS auto-starts a new one)
aws ecs stop-task \
  --cluster YOUR-CLUSTER-NAME \
  --task <task-id>
```

**Time:** 1-3 minutes per task  
**Downtime:** Brief (if only 1 task); none if multiple tasks

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0
- Valid ECS Task Execution Role with permissions for:
  - `ecr:GetAuthorizationToken`
  - `ecr:BatchCheckLayerAvailability`
  - `ecr:GetDownloadUrlForLayer`
  - `ecr:BatchGetImage`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
  - `ssm:GetParameters` (if using SSM Parameter Store)
  - `secretsmanager:GetSecretValue` (if using Secrets Manager)
- Valid ECS Task Role with application-specific permissions

## Cost Considerations

### Private Subnets (Recommended for Production)

**Monthly Costs:**
- ECS Fargate (0.25 vCPU, 1 GB): $12.23/month
- NAT Gateway: $32.40/month ⚠️ (largest cost!)
- NAT Data Transfer: $0.045/GB processed
- CloudWatch Logs: ~$2.50/month
- **Total: ~$47+ per month per task**

### Public Subnets (Not Recommended)

**Monthly Costs:**
- ECS Fargate (0.25 vCPU, 1 GB): $12.23/month
- CloudWatch Logs: ~$2.50/month
- **Total: ~$15 per month per task**

**Security Risk:** Tasks have public IPs and are internet-accessible! ❌

## Best Practices

1. **Use Commit SHAs for Image Tags**: Never use `latest` tag in production
2. **Enable Health Checks**: Ensures only healthy containers receive traffic
3. **Use Private Subnets**: Keep tasks isolated from direct internet access
4. **Leverage Secrets Manager**: For sensitive data like database passwords, API keys
5. **Monitor CloudWatch Logs**: Set up alarms for errors and anomalies
6. **Use CI/CD**: Automate deployments with GitHub Actions or similar
7. **Tag Resources Properly**: Makes cost tracking and management easier
8. **Set Appropriate Resource Limits**: Start small and scale based on metrics

## Troubleshooting

### Task Fails to Start

1. Check CloudWatch logs: `/ecs/YOUR-LOG-GROUP-NAME`
2. Verify execution role has ECR and SSM permissions
3. Ensure image exists in ECR with specified tag
4. Check secrets ARNs are valid and accessible

### Health Checks Failing

1. Verify your app exposes the health check endpoint
2. Check endpoint returns 200 status code
3. Ensure health check endpoint is accessible at `http://localhost:<port>/health`
4. Adjust `health_check_start_period` if app takes longer to start

### Container Keeps Restarting

1. Check CloudWatch logs for application errors
2. Verify environment variables and secrets are correct
3. Check memory/CPU limits are sufficient
4. Review health check configuration

### New Secrets Not Picked Up

1. Force container restart (see "Container Restart & Configuration Updates" section above)
2. Verify Task Execution Role has `ssm:GetParameters` permission
3. Check SSM parameter ARNs are correct

## License

MIT

## Author

Created as part of the VOS Terraform Modules library.

## Support

For issues, questions, or contributions, please refer to the main repository documentation.

