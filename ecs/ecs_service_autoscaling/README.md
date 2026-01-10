# ECS Service Autoscaling Module

## Overview

This Terraform module configures automatic scaling for Amazon ECS services based on CPU utilization, memory utilization, ALB request count, or scheduled patterns. It helps optimize costs by automatically adjusting the number of running tasks based on demand.

## Features

- ✅ **CPU-Based Autoscaling**: Scale based on average CPU utilization (recommended)
- ✅ **Memory-Based Autoscaling**: Scale based on average memory utilization
- ✅ **Request Count Autoscaling**: Scale based on ALB requests per target
- ✅ **Scheduled Scaling**: Scale to specific capacities at specific times
- ✅ **CloudWatch Alarms**: Monitor scaling limits and high resource usage
- ✅ **Flexible Configuration**: Enable/disable features as needed
- ✅ **Multiple Policies**: Use multiple scaling triggers simultaneously
- ✅ **Cost Optimization**: Typical savings of 30-50% vs fixed capacity

## How It Works

1. **CloudWatch monitors** your ECS service metrics (CPU, memory, requests)
2. **When metrics exceed targets**, autoscaling adds tasks (after scale-out cooldown)
3. **When metrics fall below targets**, autoscaling removes tasks (after scale-in cooldown)
4. **Capacity is constrained** between min_capacity and max_capacity

### Scaling Behavior

- **Scale Out (Add Tasks)**: Fast response to handle traffic spikes (default: 60s cooldown)
- **Scale In (Remove Tasks)**: Slow and conservative to prevent flapping (default: 300s cooldown)
- **Multiple Policies**: When using multiple triggers, autoscaling uses the most conservative approach

## Prerequisites

### Required ECS Service Configuration

Your ECS service **must** include this lifecycle rule:

```hcl
resource "aws_ecs_service" "app" {
  # ... other configuration ...
  
  # REQUIRED: Prevent Terraform from reverting autoscaling changes
  lifecycle {
    ignore_changes = [desired_count]
  }
}
```

**Why?** Autoscaling modifies `desired_count` dynamically. Without `ignore_changes`, Terraform will revert it on the next apply.

### Optional: Container Insights

Enable Container Insights for better metrics visibility:

```hcl
resource "aws_ecs_cluster" "cluster" {
  name = "my-cluster"
  
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}
```

## Usage

### Basic Example (CPU-Only Autoscaling)

```hcl
module "autoscaling" {
  source = "../../ecs/ecs_service_autoscaling"
  
  service_name     = "staging-node-app"
  cluster_name     = aws_ecs_cluster.app_cluster.name
  ecs_service_name = aws_ecs_service.app_service.name
  
  # Capacity limits
  min_capacity = 1
  max_capacity = 10
  
  # CPU-based scaling (enabled by default)
  cpu_target_value = 70.0  # Target 70% CPU utilization
  
  # Disable memory scaling
  enable_memory_scaling = false
  
  # Tagging
  environment = "staging"
  project_id  = "node-app"
}
```

### Production Example (CPU + Memory Scaling)

```hcl
module "autoscaling" {
  source = "../../ecs/ecs_service_autoscaling"
  
  service_name     = "production-api"
  cluster_name     = aws_ecs_cluster.cluster.name
  ecs_service_name = aws_ecs_service.api.name
  
  # Production capacity
  min_capacity = 2   # Always at least 2 for high availability
  max_capacity = 20
  
  # CPU scaling (aggressive for cost optimization)
  enable_cpu_scaling   = true
  cpu_target_value     = 75.0
  cpu_scale_in_cooldown  = 600  # 10 min - very conservative
  cpu_scale_out_cooldown = 30   # 30 sec - very responsive
  
  # Memory scaling (backup trigger)
  enable_memory_scaling      = true
  memory_target_value        = 85.0
  memory_scale_in_cooldown   = 600
  memory_scale_out_cooldown  = 30
  
  environment = "production"
  project_id  = "api"
}
```

### ALB Request Count Scaling

```hcl
module "autoscaling" {
  source = "../../ecs/ecs_service_autoscaling"
  
  service_name     = "web-app"
  cluster_name     = aws_ecs_cluster.cluster.name
  ecs_service_name = aws_ecs_service.web.name
  
  min_capacity = 2
  max_capacity = 15
  
  # Disable resource-based scaling
  enable_cpu_scaling    = false
  enable_memory_scaling = false
  
  # Enable request-based scaling
  enable_request_count_scaling = true
  request_count_target_value   = 1000  # 1000 requests per task per minute
  
  # Required for request count scaling
  alb_arn_suffix         = aws_lb.alb.arn_suffix
  target_group_arn_suffix = aws_lb_target_group.tg.arn_suffix
  
  environment = "production"
}
```

### Scheduled Scaling (Business Hours)

```hcl
module "autoscaling" {
  source = "../../ecs/ecs_service_autoscaling"
  
  service_name     = "batch-processor"
  cluster_name     = aws_ecs_cluster.cluster.name
  ecs_service_name = aws_ecs_service.processor.name
  
  min_capacity = 1
  max_capacity = 10
  
  # CPU-based scaling
  cpu_target_value = 70.0
  
  # Scheduled scaling for predictable patterns
  enable_scheduled_scaling = true
  scheduled_actions = [
    {
      name         = "scale-up-business-hours"
      schedule     = "cron(0 8 * * MON-FRI *)"  # 8 AM weekdays UTC
      min_capacity = 5
      max_capacity = 10
    },
    {
      name         = "scale-down-after-hours"
      schedule     = "cron(0 18 * * MON-FRI *)"  # 6 PM weekdays UTC
      min_capacity = 1
      max_capacity = 5
    }
  ]
  
  environment = "production"
}
```

### With CloudWatch Alarms

```hcl
# SNS Topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "ecs-autoscaling-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "ops@example.com"
}

module "autoscaling" {
  source = "../../ecs/ecs_service_autoscaling"
  
  service_name     = "critical-service"
  cluster_name     = aws_ecs_cluster.cluster.name
  ecs_service_name = aws_ecs_service.critical.name
  
  min_capacity = 3
  max_capacity = 20
  
  cpu_target_value = 70.0
  
  # Enable alarms
  enable_scaling_alarms = true
  alarm_sns_topic_arn   = aws_sns_topic.alerts.arn
  
  environment = "production"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| service_name | Name of the ECS service (for resource naming) | `string` | - | yes |
| cluster_name | Name of the ECS cluster | `string` | - | yes |
| ecs_service_name | Name of the ECS service (from aws_ecs_service.name) | `string` | - | yes |
| min_capacity | Minimum number of tasks | `number` | `1` | no |
| max_capacity | Maximum number of tasks | `number` | `10` | no |
| enable_cpu_scaling | Enable CPU-based autoscaling | `bool` | `true` | no |
| cpu_target_value | Target CPU utilization % (50-85) | `number` | `70.0` | no |
| cpu_scale_in_cooldown | Wait time (seconds) before removing tasks | `number` | `300` | no |
| cpu_scale_out_cooldown | Wait time (seconds) before adding tasks | `number` | `60` | no |
| enable_memory_scaling | Enable memory-based autoscaling | `bool` | `true` | no |
| memory_target_value | Target memory utilization % | `number` | `80.0` | no |
| memory_scale_in_cooldown | Wait time (seconds) before removing tasks | `number` | `300` | no |
| memory_scale_out_cooldown | Wait time (seconds) before adding tasks | `number` | `60` | no |
| enable_request_count_scaling | Enable ALB request count autoscaling | `bool` | `false` | no |
| request_count_target_value | Target requests per task per minute | `number` | `1000.0` | no |
| request_count_scale_in_cooldown | Wait time before removing tasks | `number` | `300` | no |
| request_count_scale_out_cooldown | Wait time before adding tasks | `number` | `60` | no |
| alb_arn_suffix | ALB ARN suffix (required if request scaling enabled) | `string` | `""` | no |
| target_group_arn_suffix | Target group ARN suffix (required if request scaling) | `string` | `""` | no |
| enable_scheduled_scaling | Enable scheduled scaling | `bool` | `false` | no |
| scheduled_actions | List of scheduled scaling actions | `list(object)` | `[]` | no |
| enable_scaling_alarms | Create CloudWatch alarms | `bool` | `false` | no |
| alarm_sns_topic_arn | SNS topic ARN for alarms | `string` | `""` | no |
| tags | Additional tags | `map(string)` | `{}` | no |
| environment | Environment name (added to tags) | `string` | `""` | no |
| project_id | Project identifier (added to tags) | `string` | `""` | no |

## Outputs

| Name | Description |
|------|-------------|
| scaling | Complete autoscaling configuration object |
| scaling.target | Autoscaling target details (resource_id, min/max capacity) |
| scaling.policies | Scaling policies (cpu, memory, request_count) |
| scaling.scheduled_actions | Scheduled scaling configuration |
| scaling.alarms | CloudWatch alarms (if enabled) |

### Output Usage

```bash
# View complete autoscaling configuration
terraform output -json autoscaling

# Get min/max capacity
terraform output -json autoscaling | jq '.target.min_capacity'
terraform output -json autoscaling | jq '.target.max_capacity'

# Check if CPU scaling is enabled
terraform output -json autoscaling | jq '.policies.cpu.enabled'
```

## Scaling Target Values Guide

### CPU Target Value

| Value | Use Case | Cost | Performance |
|-------|----------|------|-------------|
| 50% | Development, testing | Higher | Excellent headroom |
| 70% | Production (recommended) | Balanced | Good headroom |
| 80% | Cost-optimized production | Lower | Moderate headroom |
| 85% | Aggressive cost optimization | Lowest | Minimal headroom |

### Memory Target Value

| Value | Use Case | Reasoning |
|-------|----------|-----------|
| 70% | Memory-intensive apps | Conservative |
| 80% | General apps (recommended) | Balanced |
| 90% | Low memory variation | Aggressive |

**Note**: Memory target is usually higher than CPU (e.g., 80% vs 70%) to prevent premature scaling based on memory alone.

### Request Count Target Value

Formula: **Target = (Requests per task capacity) × (Safety factor)**

Examples:
- Task can handle 2000 req/min → Set target to 1500 (75% utilization)
- Task can handle 1000 req/min → Set target to 800 (80% utilization)

## Cooldown Period Guide

### Scale-Out Cooldown (Adding Tasks)

| Value | Use Case |
|-------|----------|
| 30s | Very aggressive (flash sales, viral content) |
| 60s | Balanced (recommended) |
| 120s | Conservative (stable loads) |

**Shorter cooldown** = Faster response to traffic spikes

### Scale-In Cooldown (Removing Tasks)

| Value | Use Case |
|-------|----------|
| 180s (3 min) | Aggressive cost optimization |
| 300s (5 min) | Balanced (recommended) |
| 600s (10 min) | Very conservative (prevent flapping) |

**Longer cooldown** = More stable, less frequent scaling changes

## Cost Impact Analysis

### Example: E-commerce Application

**Fixed Capacity (No Autoscaling):**
- 5 tasks × 24 hours × 30 days
- Cost: 3,600 task-hours/month

**With Autoscaling (Traffic Pattern: Peak during business hours):**
- Night/Weekend: 1-2 tasks
- Business hours: 3-8 tasks
- Average: ~2.5 tasks
- Cost: 1,800 task-hours/month
- **Savings: 50%** 💰

### Fargate Cost Breakdown

For 0.25 vCPU + 1 GB memory (per task):
- Hourly: $0.01675
- Daily (1 task): $0.40
- Monthly (1 task): $12.23

**Autoscaling Impact:**
- Min 1, Max 10: $12.23 - $122.30/month range
- Average 3 tasks: ~$36.69/month
- vs Fixed 5 tasks: ~$61.15/month
- **Savings: ~40%**

## Monitoring & Troubleshooting

### View Current Task Count

```bash
aws ecs describe-services \
  --cluster my-cluster \
  --services my-service \
  --query 'services[0].{Running:runningCount,Desired:desiredCount,Min:deployments[0].desiredCount}'
```

### View Scaling Activity

```bash
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id service/my-cluster/my-service
```

### CloudWatch Metrics to Monitor

- `CPUUtilization` - ECS service CPU usage
- `MemoryUtilization` - ECS service memory usage
- `DesiredTaskCount` - Current autoscaling target
- `RunningTaskCount` - Actual running tasks
- `RequestCountPerTarget` - ALB requests per target

### Common Issues

#### Tasks Not Scaling Out

**Symptoms**: High CPU/memory but no new tasks

**Possible causes**:
1. Scale-out cooldown period not elapsed yet (wait 60s)
2. Max capacity reached
3. ECS service has `lifecycle { ignore_changes = [desired_count] }` missing

**Solution**:
```bash
# Check current capacity
aws application-autoscaling describe-scalable-targets \
  --service-namespace ecs \
  --resource-ids service/my-cluster/my-service
```

#### Tasks Scaling Too Aggressively

**Symptoms**: Constant scaling up/down (flapping)

**Possible causes**:
1. Cooldown periods too short
2. Target values too sensitive
3. Uneven load distribution

**Solution**:
- Increase `scale_in_cooldown` to 600s (10 min)
- Increase `scale_out_cooldown` to 120s (2 min)
- Adjust target values (CPU 70% → 75%)

#### Terraform Reverting desired_count

**Symptoms**: Autoscaling works, then Terraform reverts task count

**Solution**:
```hcl
resource "aws_ecs_service" "app" {
  # ... config ...
  
  # Add this!
  lifecycle {
    ignore_changes = [desired_count]
  }
}
```

## Best Practices

1. **Start Conservative**: Begin with higher target values (CPU 60%, Memory 70%) and tune down
2. **Monitor First**: Run without autoscaling for 1-2 weeks to understand baseline
3. **Use Multiple Policies**: Combine CPU + Memory for redundancy
4. **Set Appropriate Limits**: 
   - Min: At least 2 for high availability
   - Max: 3-5x your average load
5. **Longer Scale-In Cooldowns**: Prevent flapping (300-600s recommended)
6. **Enable Alarms**: Get notified when hitting capacity limits
7. **Test Scaling**: Simulate load to verify autoscaling behavior
8. **Review Regularly**: Adjust targets based on actual performance data

## Scheduled Scaling Examples

### Business Hours (8 AM - 6 PM Weekdays)

```hcl
scheduled_actions = [
  {
    name         = "scale-up-business-hours"
    schedule     = "cron(0 8 * * MON-FRI *)"
    min_capacity = 3
    max_capacity = 10
  },
  {
    name         = "scale-down-after-hours"
    schedule     = "cron(0 18 * * MON-FRI *)"
    min_capacity = 1
    max_capacity = 5
  }
]
```

### Batch Processing (Nightly at 2 AM)

```hcl
scheduled_actions = [
  {
    name         = "scale-up-batch-processing"
    schedule     = "cron(0 2 * * * *)"
    min_capacity = 10
    max_capacity = 20
  },
  {
    name         = "scale-down-batch-complete"
    schedule     = "cron(0 6 * * * *)"
    min_capacity = 1
    max_capacity = 5
  }
]
```

### Cron Schedule Format

```
cron(minute hour day month weekday year)
```

Examples:
- `cron(0 8 * * MON-FRI *)` - 8 AM weekdays
- `cron(0 2 * * * *)` - 2 AM daily
- `cron(0 0 1 * * *)` - Midnight on 1st of month

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0
- Existing ECS cluster and service
- ECS service with `lifecycle { ignore_changes = [desired_count] }`

## Related Modules

- [ECS Task Definition](../task_definitions/node_js/basic_node_js_task_definition/) - Create ECS task definitions
- [ECS Task Execution Role](../ecs_task_execution_role/) - IAM role for ECS
- [ECS Task Role](../ecs_task_role/) - Application runtime permissions

## License

MIT

## Author

Created as part of the VOS Terraform Modules library.

## Support

For issues, questions, or contributions, please refer to the main repository documentation.

