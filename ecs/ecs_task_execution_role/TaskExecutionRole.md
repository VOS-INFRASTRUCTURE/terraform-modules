# ECS Task Execution Role Module

## Overview

This module creates an **IAM role** that grants Amazon ECS the permissions needed to:
- Pull container images from **Amazon ECR** (Elastic Container Registry)
- Write logs to **CloudWatch Logs**
- Retrieve secrets from **AWS Secrets Manager** or **Systems Manager Parameter Store** (if configured)

This is a **required role** for ECS Fargate tasks and is separate from the **Task Role** (which grants permissions to the application running inside the container).

---

## What Does This Role Do?

| Permission | Purpose |
|-----------|---------|
| **ECR Image Pull** | Allows ECS to authenticate and download Docker images from your private ECR repositories |
| **CloudWatch Logs** | Enables ECS to create log streams and write container logs to CloudWatch |
| **Secrets Access** (optional) | If your task definition references secrets, this role retrieves them during container startup |

---


✅ Option 1 — ECS injects secrets as env vars
✔️ Permissions

You are correct:

secretsmanager:GetSecretValue is needed on the Task Execution Role

It is used only at task startup (container “spin-up”)

Why execution role?

ECS agent (not your app) fetches the secret

ECS injects it into the container as an environment variable

✔️ Secret updates behavior

You are 100% correct here:

Changing the secret value in AWS Console does NOT update running containers

✔️ Existing containers keep the old value
✔️ New tasks get the new value
✔️ Requires:

service redeploy

task restart

scaling event

This is expected and by design.


## Usage in Your Infrastructure

### In Staging

```hcl
module "ecs_task_execution_role" {
  source = "../../staging-infrastructure/modules/ecs_task_execution_role"
  
  env        = var.env         # e.g., "staging"
  project_id = var.project_id  # e.g., "cerpac"
}

# Reference in task definition
resource "aws_ecs_task_definition" "node_app" {
  execution_role_arn = module.ecs_task_execution_role.role_arn
  # ... rest of task definition
}
```

### In Production

```hcl
module "ecs_task_execution_role" {
  source = "../../production-infrastructure/modules/ecs_task_execution_role"
  
  env        = "production"
  project_id = "cerpac"
}
```

---

## Inputs

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `env` | string | Yes | - | Environment name (e.g., staging, production) |
| `project_id` | string | Yes | - | Project identifier (used in resource naming) |

---

## Outputs

| Output | Description | Example Value |
|--------|-------------|---------------|
| `role_arn` | The ARN of the created IAM role | `arn:aws:iam::820242908282:role/staging-ecs-task-execution-role` |
| `role_name` | The name of the IAM role | `staging-ecs-task-execution-role` |

---

## Permissions Granted

This role includes the AWS-managed policy:
```
arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

Which provides:
- `ecr:GetAuthorizationToken`
- `ecr:BatchCheckLayerAvailability`
- `ecr:GetDownloadUrlForLayer`
- `ecr:BatchGetImage`
- `logs:CreateLogStream`
- `logs:PutLogEvents`

---

## Difference: Task Execution Role vs Task Role

| Aspect | Task Execution Role | Task Role |
|--------|---------------------|-----------|
| **Who uses it?** | ECS service (AWS infrastructure) | Your application code |
| **When is it used?** | During task startup (pull image, fetch secrets) | While the container is running |
| **Example permissions** | Pull from ECR, write CloudWatch logs | Access S3 buckets, read DynamoDB, send SES emails |
| **Required?** | **Yes** (for Fargate) | Optional (only if your app needs AWS API access) |

---

## Example: Full ECS Task with Both Roles

```hcl
# Execution role (this module)
module "ecs_task_execution_role" {
  source     = "./modules/ecs_task_execution_role"
  env        = "staging"
  project_id = "cerpac"
}

# Task role (for application permissions)
module "ecs_task_role" {
  source     = "./modules/ecs_task_role"
  env        = "staging"
  project_id = "cerpac"
}

# Task definition using both
resource "aws_ecs_task_definition" "app" {
  family = "staging-ecs-node-app-task"
  
  execution_role_arn = module.ecs_task_execution_role.role_arn  # ← ECS uses this
  task_role_arn      = module.ecs_task_role.role_arn           # ← Your app uses this
  
  # ... container definitions
}
```

---

## Troubleshooting

### Error: "Unable to pull secrets or registry auth"

**Cause**: The task execution role lacks permissions to access ECR or the subnets can't reach ECR endpoints.

**Solutions**:
1. Verify the role has `AmazonECSTaskExecutionRolePolicy` attached
2. Check that subnets have:
   - NAT Gateway for internet access, OR
   - VPC endpoints for `ecr.api`, `ecr.dkr`, and `logs`

### Error: "Task cannot pull registry auth from Amazon ECR"

**Cause**: Network timeout when accessing ECR from private subnets.

**Solution**: Add VPC endpoints or ensure NAT Gateway is configured:
```hcl
# In your VPC module
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}
```

---

## Related Documentation

- [AWS ECS Task Execution IAM Role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
- [ECS Task Role vs Execution Role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- Task Role Module: `modules/ecs_task_role/`
- ECS Service Configuration: `node_app_service.tf`

---

## Tags Applied

All resources created by this module are tagged with:
- `Environment`: Value from `var.env`
- `ManagedBy`: `Terraform`
- `Module`: `ecs_task_execution_role`

