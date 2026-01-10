# Usage Examples for Basic Node.js Task Definition Module

This document provides practical examples of how to use the `basic_node_js_task_definition` module in real-world scenarios.

## Example 1: Simple Node.js API (Staging Environment)

This example shows a basic setup for a staging Node.js API with minimal configuration.

```hcl
# main.tf

# ECR Repository
module "ecr_node_api" {
  source = "../../ecr"
  
  repository_name = "staging-node-api"
  environment     = "staging"
}

# Task Execution Role
module "ecs_task_execution_role" {
  source = "../../ecs/ecs_task_execution_role"
  
  role_name   = "staging-node-api-execution-role"
  environment = "staging"
}

# Task Role (application runtime permissions)
module "ecs_task_role" {
  source = "../../ecs/ecs_task_role"
  
  role_name   = "staging-node-api-task-role"
  environment = "staging"
}

# SSM Parameters for configuration
resource "aws_ssm_parameter" "node_env" {
  name  = "/staging/node-api/NODE_ENV"
  type  = "String"
  value = "production"
}

resource "aws_ssm_parameter" "port" {
  name  = "/staging/node-api/PORT"
  type  = "String"
  value = "3000"
}

# Task Definition
module "node_api_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  # Task Configuration
  task_family    = "staging-node-api-task"
  container_name = "node-api-container"
  
  # Container Image
  ecr_repository_url = module.ecr_node_api.ecr_repository.url
  image_tag          = var.app_version  # e.g., "abc123" from GitHub Actions
  
  # IAM Roles
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  
  # AWS Configuration
  region = var.aws_region
  
  # Logging
  log_group_name     = "/ecs/staging-node-api"
  log_retention_days = 7  # Keep staging logs for 1 week
  
  # Secrets from SSM
  secrets = [
    {
      name      = "NODE_ENV"
      valueFrom = aws_ssm_parameter.node_env.arn
    },
    {
      name      = "PORT"
      valueFrom = aws_ssm_parameter.port.arn
    }
  ]
  
  # Static environment variables
  environment_variables = [
    {
      name  = "APP_NAME"
      value = "staging-node-api"
    }
  ]
  
  # Tagging
  environment = "staging"
  project_id  = "node-api"
}

# Output for use in ECS Service
output "task_definition_arn" {
  value = module.node_api_task.task_definition_arn
}
```

---

## Example 2: Production Node.js App with Database and External Services

This example shows a production setup with increased resources, database connections, and external service integrations.

```hcl
# main.tf

# SSM Parameters
resource "aws_ssm_parameter" "app_config" {
  for_each = {
    "NODE_ENV"            = "production"
    "PORT"                = "3000"
    "LOG_LEVEL"           = "info"
    "REQUEST_TIMEOUT_MS"  = "30000"
    "MAX_UPLOAD_SIZE_MB"  = "10"
    "ENABLE_CORS"         = "true"
  }
  
  name  = "/production/node-app/${each.key}"
  type  = "String"
  value = each.value
}

# Secrets Manager for sensitive data
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "production/node-app/database"
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    host     = module.rds.endpoint
    port     = 3306
    database = "production_db"
    username = "app_user"
    password = random_password.db_password.result
  })
}

# Task Definition
module "production_node_app_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  # Task Configuration
  task_family    = "production-node-app-task"
  container_name = "node-app-container"
  
  # Container Image
  ecr_repository_url = module.ecr_node_app.ecr_repository.url
  image_tag          = var.app_version
  
  # IAM Roles
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  
  # AWS Configuration
  region = "us-east-1"
  
  # Increased resources for production
  cpu    = "1024"   # 1 vCPU
  memory = "2048"   # 2 GB
  
  # Logging
  log_group_name     = "/ecs/production-node-app"
  log_retention_days = 90  # Keep production logs for 3 months
  
  # Configuration from SSM
  secrets = concat(
    # App configuration from SSM
    [
      for key in keys(aws_ssm_parameter.app_config) : {
        name      = key
        valueFrom = aws_ssm_parameter.app_config[key].arn
      }
    ],
    # Database credentials from Secrets Manager
    [
      {
        name      = "DB_HOST"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:host::"
      },
      {
        name      = "DB_PORT"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:port::"
      },
      {
        name      = "DB_NAME"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:database::"
      },
      {
        name      = "DB_USER"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
      }
    ]
  )
  
  # Static environment variables
  environment_variables = [
    {
      name  = "CONTAINER_MODE"
      value = "app"
    },
    {
      name  = "AWS_REGION"
      value = "us-east-1"
    }
  ]
  
  # Production health checks (more frequent)
  health_check_endpoint     = "/api/health"
  health_check_interval     = 15
  health_check_timeout      = 10
  health_check_retries      = 5
  health_check_start_period = 120
  
  # Tagging
  environment = "production"
  project_id  = "critical-app"
  
  tags = {
    Team        = "Platform"
    CostCenter  = "Engineering"
    Compliance  = "HIPAA"
  }
}
```

---

## Example 3: Multi-Container Setup (App + Worker)

This example shows how to create separate task definitions for a web app and a background worker using the same codebase.

```hcl
# Shared SSM Parameters
resource "aws_ssm_parameter" "shared_config" {
  for_each = {
    "NODE_ENV"   = "production"
    "LOG_LEVEL"  = "info"
    "QUEUE_URL"  = aws_sqs_queue.tasks.url
  }
  
  name  = "/production/app-platform/${each.key}"
  type  = "String"
  value = each.value
}

# Web App Task Definition
module "web_app_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family    = "production-web-app-task"
  container_name = "web-app-container"
  
  ecr_repository_url = module.ecr_app.ecr_repository.url
  image_tag          = var.app_version
  
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.web_task_role.role.arn
  
  region = var.aws_region
  
  # Web app resources
  cpu    = "512"
  memory = "1024"
  
  container_port = 3000
  
  log_group_name = "/ecs/production-web-app"
  
  secrets = [
    for key in keys(aws_ssm_parameter.shared_config) : {
      name      = key
      valueFrom = aws_ssm_parameter.shared_config[key].arn
    }
  ]
  
  environment_variables = [
    {
      name  = "CONTAINER_MODE"
      value = "web"
    }
  ]
  
  health_check_endpoint = "/health"
  
  environment = "production"
  project_id  = "app-platform"
}

# Worker Task Definition
module "worker_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family    = "production-worker-task"
  container_name = "worker-container"
  
  ecr_repository_url = module.ecr_app.ecr_repository.url
  image_tag          = var.app_version
  
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.worker_task_role.role.arn  # Different permissions for worker
  
  region = var.aws_region
  
  # Worker resources (may need more CPU)
  cpu    = "1024"
  memory = "2048"
  
  container_port = 3000  # Even workers should expose health check endpoint
  
  log_group_name = "/ecs/production-worker"
  
  secrets = [
    for key in keys(aws_ssm_parameter.shared_config) : {
      name      = key
      valueFrom = aws_ssm_parameter.shared_config[key].arn
    }
  ]
  
  environment_variables = [
    {
      name  = "CONTAINER_MODE"
      value = "worker"
    },
    {
      name  = "WORKER_CONCURRENCY"
      value = "5"
    }
  ]
  
  health_check_endpoint = "/health"
  
  environment = "production"
  project_id  = "app-platform"
}
```

---

## Example 4: Development Environment with Terraform-Managed Definitions

This example shows a development setup where Terraform fully manages container definitions (no CI/CD overrides).

```hcl
module "dev_app_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family    = "dev-node-app-task"
  container_name = "dev-app-container"
  
  ecr_repository_url = module.ecr_dev_app.ecr_repository.url
  image_tag          = "development-latest"  # OK for dev environment
  
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  
  region = "us-east-1"
  
  # Minimal resources for dev
  cpu    = "256"
  memory = "512"
  
  log_group_name     = "/ecs/dev-node-app"
  log_retention_days = 3  # Short retention for dev
  
  # Allow Terraform to manage everything
  ignore_changes_to_container_definitions = false
  
  secrets = [
    {
      name      = "NODE_ENV"
      valueFrom = aws_ssm_parameter.dev_node_env.arn
    }
  ]
  
  environment_variables = [
    {
      name  = "DEBUG"
      value = "true"
    },
    {
      name  = "ENVIRONMENT"
      value = "development"
    }
  ]
  
  # Relaxed health checks for dev
  health_check_interval     = 60
  health_check_start_period = 30
  
  environment = "development"
  project_id  = "dev-sandbox"
}
```

---

## Example 5: Custom Port and Health Check Endpoint

This example shows how to use custom ports and health check configurations.

```hcl
module "custom_api_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family    = "staging-custom-api-task"
  container_name = "custom-api-container"
  
  ecr_repository_url = module.ecr_api.ecr_repository.url
  image_tag          = var.app_version
  
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  
  region = "us-west-2"
  
  # Custom port (instead of default 3000)
  container_port     = 8080
  container_protocol = "tcp"
  
  log_group_name = "/ecs/staging-custom-api"
  
  # Custom health check configuration
  health_check_enabled      = true
  health_check_endpoint     = "/api/v1/health/check"
  health_check_interval     = 20
  health_check_timeout      = 10
  health_check_retries      = 3
  health_check_start_period = 90
  
  environment = "staging"
  project_id  = "custom-api"
}
```

---

## Example 6: Using External Log Group

This example shows how to use an externally created CloudWatch log group.

```hcl
# Create log group outside the module
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/centralized-logs/node-app"
  retention_in_days = 365  # 1 year retention
  
  tags = {
    ManagedBy = "Security-Team"
  }
}

module "node_app_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family    = "prod-node-app-task"
  container_name = "node-app-container"
  
  ecr_repository_url = module.ecr_app.ecr_repository.url
  image_tag          = var.app_version
  
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  
  region = "us-east-1"
  
  # Use external log group
  log_group_name  = aws_cloudwatch_log_group.app_logs.name
  create_log_group = false  # Don't create, use existing
  
  environment = "production"
  project_id  = "node-app"
}
```

---

## Complete Integration Example

Here's a complete example showing how to integrate this module with an ECS cluster and service:

```hcl
# ECR Repository
module "ecr_app" {
  source = "../../ecr"
  
  repository_name = "staging-node-app"
  environment     = "staging"
}

# IAM Roles
module "ecs_task_execution_role" {
  source = "../../ecs/ecs_task_execution_role"
  
  role_name   = "staging-app-execution-role"
  environment = "staging"
}

module "ecs_task_role" {
  source = "../../ecs/ecs_task_role"
  
  role_name   = "staging-app-task-role"
  environment = "staging"
  
  # Grant S3 access for file uploads
  enable_s3_access = true
  s3_bucket_arns   = [aws_s3_bucket.uploads.arn]
}

# Configuration
resource "aws_ssm_parameter" "app_config" {
  for_each = {
    "NODE_ENV" = "production"
    "PORT"     = "3000"
  }
  
  name  = "/staging/app/${each.key}"
  type  = "String"
  value = each.value
}

# Task Definition
module "app_task_definition" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  task_family        = "staging-app-task"
  container_name     = "app-container"
  ecr_repository_url = module.ecr_app.ecr_repository.url
  image_tag          = var.app_version
  execution_role_arn = module.ecs_task_execution_role.role.arn
  task_role_arn      = module.ecs_task_role.role.arn
  region             = var.aws_region
  log_group_name     = "/ecs/staging-app"
  
  secrets = [
    for key in keys(aws_ssm_parameter.app_config) : {
      name      = key
      valueFrom = aws_ssm_parameter.app_config[key].arn
    }
  ]
  
  environment = "staging"
  project_id  = "app"
}

# ECS Cluster
resource "aws_ecs_cluster" "app_cluster" {
  name = "staging-app-cluster"
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "staging-app-ecs-tasks"
  description = "Allow inbound traffic to ECS tasks"
  vpc_id      = var.vpc_id
  
  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "staging-app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = module.app_task_definition.task_definition_arn
  desired_count   = 2
  launch_type     = "FARGATE"
  
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = false
  }
  
  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = module.app_task_definition.container_name
    container_port   = module.app_task_definition.container_port
  }
  
  depends_on = [aws_lb_listener.app]
}
```

---

## Tips and Best Practices

1. **Image Tags**: Use commit SHAs or semantic versions, never `latest` in production
2. **Resource Sizing**: Start small and scale based on CloudWatch metrics
3. **Health Checks**: Always implement a `/health` endpoint in your Node.js app
4. **Secrets**: Use Secrets Manager for sensitive data, SSM for configuration
5. **Logging**: Set appropriate retention periods based on compliance requirements
6. **Tagging**: Use consistent tags for cost allocation and resource management
7. **CI/CD**: Let GitHub Actions manage image tags, set `ignore_changes_to_container_definitions = true`
8. **Security**: Use private subnets with NAT Gateway for production workloads

