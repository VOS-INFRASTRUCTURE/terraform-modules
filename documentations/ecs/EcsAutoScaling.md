# ECS Auto Scaling Guide

## Overview

ECS Auto Scaling automatically adjusts the number of running tasks based on demand, ensuring your application has the right capacity without manual intervention.

**Benefits:**
- ✅ Automatically handles traffic spikes
- ✅ Reduces costs during low-traffic periods
- ✅ Maintains performance during high load
- ✅ No manual intervention required

**Cost Model:**
- Scale up: More tasks = higher cost (more vCPU/memory)
- Scale down: Fewer tasks = lower cost
- You only pay for what you use

---

## Auto Scaling Components

### 1. Scalable Target
Defines the ECS service to scale and the min/max task count limits.

### 2. Scaling Policies
Rules that determine when and how to scale (up or down).

### 3. CloudWatch Alarms (Implicit)
Created automatically by target tracking policies to monitor metrics.

---

## Scaling Policy Types

### Type 1: Target Tracking (Recommended) ⭐

**How it works:**
- You set a target value for a metric (e.g., CPU = 70%)
- Auto Scaling automatically adds/removes tasks to maintain that target
- Similar to a thermostat maintaining temperature

**Best for:**
- Most applications
- Predictable scaling behavior
- Simple configuration

**Example Metrics:**
- Average CPU utilization
- Average memory utilization
- ALB request count per target
- Custom CloudWatch metrics

---

### Type 2: Step Scaling

**How it works:**
- Define thresholds and scaling actions
- Different scaling amounts based on how far the metric deviates

**Example:**
- CPU 50-70%: Add 1 task
- CPU 70-85%: Add 2 tasks
- CPU >85%: Add 3 tasks

**Best for:**
- Complex scaling requirements
- Fine-grained control
- Gradual scaling responses

---

### Type 3: Scheduled Scaling

**How it works:**
- Scale to specific task count at specific times
- Based on known traffic patterns

**Example:**
- 8 AM: Scale to 5 tasks (business hours start)
- 6 PM: Scale to 2 tasks (business hours end)
- Weekends: Scale to 1 task

**Best for:**
- Predictable traffic patterns
- Business hour workloads
- Batch processing schedules

---

## Recommended Configuration for Node.js App

### Basic Setup (Good for Most Apps)

```hcl
# Minimum: 1 task (always at least 1 running)
# Maximum: 10 tasks (cap to control costs)
# Target: 70% CPU utilization
```

**What this does:**
- Starts with 1 task
- Scales up when CPU > 70% (adds tasks)
- Scales down when CPU < 70% (removes tasks)
- Never goes below 1 task (app stays available)
- Never exceeds 10 tasks (cost protection)

**Cost Example:**
```
Low traffic (1 task):   $15/month
Medium traffic (3 tasks): $45/month
High traffic (10 tasks): $150/month
```

---

## Complete Terraform Configuration

### Step 1: Update ECS Service (Remove `desired_count`)

```hcl
resource "aws_ecs_service" "node_app_service" {
  name            = "${var.env}-ecs-node-app-service"
  cluster         = aws_ecs_cluster.node_app_cluster.id
  task_definition = aws_ecs_task_definition.node_app_task_definition.arn
  
  # Remove this when using auto scaling:
  # desired_count = 1
  
  # Or set it as the initial count (auto scaling will adjust it):
  desired_count = 1  # Initial count, auto scaling takes over after first deployment
  
  launch_type = "FARGATE"
  
  # ...rest of configuration...
  
  lifecycle {
    ignore_changes = [
      task_definition,
      desired_count  # Important: Ignore changes to prevent Terraform from reverting auto scaling
    ]
  }
}
```

---

### Step 2: Create Auto Scaling Target

```hcl
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 10  # Maximum number of tasks
  min_capacity       = 1   # Minimum number of tasks (always at least 1)
  resource_id        = "service/${aws_ecs_cluster.node_app_cluster.name}/${aws_ecs_service.node_app_service.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}
```

---

### Step 3: Create Scaling Policy (Target Tracking - CPU)

```hcl
resource "aws_appautoscaling_policy" "ecs_cpu_policy" {
  name               = "${var.env}-ecs-node-app-cpu-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 70.0  # Target 70% CPU utilization
    scale_in_cooldown  = 300   # Wait 5 minutes before scaling down (prevents flapping)
    scale_out_cooldown = 60    # Wait 1 minute before scaling up (respond quickly)

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
```

---

### Step 4: Create Scaling Policy (Target Tracking - Memory)

```hcl
resource "aws_appautoscaling_policy" "ecs_memory_policy" {
  name               = "${var.env}-ecs-node-app-memory-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 80.0  # Target 80% memory utilization
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
```

**Note:** When using multiple policies, auto scaling will scale based on whichever metric triggers first.

---

### Step 5 (Optional): ALB Request Count Scaling

Scale based on incoming requests rather than resource utilization:

```hcl
resource "aws_appautoscaling_policy" "ecs_request_count_policy" {
  name               = "${var.env}-ecs-node-app-request-autoscaling"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = 1000.0  # Target 1000 requests per task per minute
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.node_app_alb.arn_suffix}/${aws_lb_target_group.node_app_tg.arn_suffix}"
    }
  }
}
```

---

## Scaling Behavior Examples

### Example 1: CPU-Based Scaling

**Initial State:**
- 1 task running
- CPU utilization: 30%

**Scenario: Traffic Spike**
```
t=0s:   Traffic increases
t=30s:  CPU rises to 75% (above 70% target)
t=60s:  Scale-out cooldown expires
        → Auto Scaling adds 1 task (now 2 tasks)
t=90s:  Load distributed across 2 tasks
        CPU drops to 50% (below 70% target)
        
Steady state: 2 tasks at ~50% CPU
```

**Scenario: Traffic Decreases**
```
t=0s:   Traffic decreases
t=30s:  CPU drops to 40% (below 70% target)
t=330s: Scale-in cooldown expires (5 minutes)
        → Auto Scaling removes 1 task (now 1 task)
        
Steady state: 1 task at ~60% CPU
```

---

### Example 2: Memory-Based Scaling

**Initial State:**
- 1 task running
- Memory utilization: 50%

**Scenario: Memory Leak or Heavy Data Processing**
```
t=0s:   Memory-intensive operation starts
t=60s:  Memory rises to 85% (above 80% target)
t=120s: Scale-out cooldown expires
        → Auto Scaling adds 1 task (now 2 tasks)
t=150s: Load distributed, memory drops to 55%
        
Steady state: 2 tasks at ~55% memory
```

---

## Scaling Parameters Explained

### min_capacity
**Minimum number of tasks.**

- **1**: Always at least 1 task running (recommended for production)
- **0**: Can scale to zero (saves costs but causes downtime)
- **2**: Minimum redundancy (high availability)

**Recommendation:** Start with `1` for staging, `2` for production.

---

### max_capacity
**Maximum number of tasks (cost control).**

- **10**: Moderate limit for small apps
- **20**: Medium traffic apps
- **50**: High traffic apps
- **100+**: Very high scale

**How to choose:**
```
Expected peak traffic ÷ requests per task = max_capacity

Example:
10,000 req/min peak ÷ 1,000 req/min per task = 10 tasks
Add 20% buffer: 10 × 1.2 = 12 tasks
```

**Recommendation:** Start with `10`, monitor, adjust based on metrics.

---

### target_value
**Target metric value to maintain.**

**CPU:**
- 50%: Conservative (more headroom, higher cost)
- 70%: Balanced (recommended)
- 85%: Aggressive (lower cost, less headroom)

**Memory:**
- 70%: Conservative
- 80%: Balanced (recommended)
- 90%: Aggressive (risky - OOM kills)

**Recommendation:**
- CPU: 70%
- Memory: 80%

---

### scale_in_cooldown
**Wait time before scaling down (seconds).**

- **60s**: Fast scale-down (cost-optimized, risk of flapping)
- **300s** (5 min): Balanced (recommended)
- **600s** (10 min): Conservative (prevents frequent changes)

**Why longer cooldown for scale-in?**
- Prevents "flapping" (rapid scale up/down cycles)
- Gives time for traffic to stabilize
- Avoids disrupting stable workloads

**Recommendation:** 300 seconds (5 minutes)

---

### scale_out_cooldown
**Wait time before scaling up (seconds).**

- **30s**: Very aggressive (respond to spikes quickly)
- **60s**: Balanced (recommended)
- **120s**: Conservative (slower response)

**Why shorter cooldown for scale-out?**
- Respond quickly to traffic spikes
- Prevent performance degradation
- User experience is priority over cost

**Recommendation:** 60 seconds (1 minute)

---

## Cost Analysis

### Scenario 1: Fixed 3 Tasks (No Auto Scaling)

```
3 tasks × 0.25 vCPU × $0.04048/vCPU-hour × 730 hours = $22.16/month
3 tasks × 1 GB RAM × $0.004445/GB-hour × 730 hours   = $9.74/month
─────────────────────────────────────────────────────────────
Total: $31.90/month (always 3 tasks, even at 2 AM)
```

---

### Scenario 2: Auto Scaling (1-10 tasks, avg 2.5 tasks)

**Traffic Pattern:**
- Off-peak (16 hours/day): 1 task
- Peak (8 hours/day): 5 tasks
- Average: (1 × 16 + 5 × 8) ÷ 24 = 2.5 tasks

```
2.5 tasks × 0.25 vCPU × $0.04048/vCPU-hour × 730 hours = $18.47/month
2.5 tasks × 1 GB RAM × $0.004445/GB-hour × 730 hours   = $8.11/month
─────────────────────────────────────────────────────────────
Total: $26.58/month (scales based on demand)

Savings: $31.90 - $26.58 = $5.32/month (17% savings)
```

**Better savings with more pronounced traffic patterns:**

If traffic is very spiky (1 task 20 hours/day, 10 tasks 4 hours/day):
```
Average: (1 × 20 + 10 × 4) ÷ 24 = 2.5 tasks (same average)
But actual pattern provides better resource utilization
Potential savings: 30-40% vs fixed capacity
```

---

## Monitoring Auto Scaling

### CloudWatch Metrics to Monitor

```bash
# View scaling activity
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id "service/staging-ecs-node-app-cluster/staging-ecs-node-app-service" \
  --max-results 20
```

**CloudWatch Dashboard Widgets:**

1. **ECS Service Desired vs Running Count**
   - Metric: `DesiredTaskCount` and `RunningTaskCount`
   - Namespace: `AWS/ECS`

2. **CPU Utilization**
   - Metric: `CPUUtilization`
   - Shows when scaling is triggered

3. **Memory Utilization**
   - Metric: `MemoryUtilization`
   - Confirms memory-based scaling

4. **ALB Request Count**
   - Metric: `RequestCountPerTarget`
   - Correlate traffic with scaling events

---

### View Scaling Events

**Via AWS Console:**
1. Go to **ECS** → **Clusters** → Your cluster
2. Select **Services** → Your service
3. Click **Auto Scaling** tab
4. View **Scaling history**

**Via CloudWatch:**
1. **CloudWatch** → **Alarms**
2. Look for alarms created by auto scaling (auto-generated names)
3. View alarm history to see scaling triggers

---

## Troubleshooting

### Problem: Service Not Scaling Up

**Possible Causes:**
1. Max capacity reached
2. Scale-out cooldown still active
3. Metric not reaching threshold
4. IAM permissions missing

**Solutions:**
```bash
# Check current task count vs max
aws ecs describe-services \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].{desired:desiredCount,running:runningCount}'

# Check scaling activities
aws application-autoscaling describe-scaling-activities \
  --service-namespace ecs \
  --resource-id "service/staging-ecs-node-app-cluster/staging-ecs-node-app-service"

# Check metric values
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=staging-ecs-node-app-service Name=ClusterName,Value=staging-ecs-node-app-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

---

### Problem: Service Not Scaling Down

**Possible Causes:**
1. Min capacity reached (already at minimum)
2. Scale-in cooldown still active (5 minutes default)
3. Metric still above target

**Solutions:**
- Wait for cooldown period to expire
- Verify metric has dropped below target
- Check scaling history for recent scale-out events

---

### Problem: Flapping (Rapid Scale Up/Down)

**Symptoms:**
- Tasks constantly being added and removed
- Service never stabilizes

**Causes:**
- Cooldown periods too short
- Target value too close to actual usage
- Application has spiky resource usage

**Solutions:**
```hcl
# Increase cooldown periods
scale_in_cooldown  = 600  # 10 minutes instead of 5
scale_out_cooldown = 120  # 2 minutes instead of 1

# Adjust target value (add more buffer)
target_value = 60.0  # Instead of 70.0
```

---

## Best Practices

### ✅ DO

1. **Start with target tracking on CPU** - Simplest and most reliable
2. **Use longer scale-in cooldowns** - Prevents flapping (5-10 minutes)
3. **Monitor for 1-2 weeks** - Adjust based on actual traffic patterns
4. **Set min_capacity ≥ 1** - Ensures availability
5. **Set reasonable max_capacity** - Prevents runaway costs
6. **Add CloudWatch alarms** - Alert on max capacity reached
7. **Test scaling behavior** - Simulate load to verify scaling works
8. **Use Container Insights** - Better visibility into resource usage

### ❌ DON'T

1. **Don't set target too high** - 90% CPU/memory leaves no headroom
2. **Don't use min_capacity = 0** - Causes cold starts and downtime
3. **Don't forget lifecycle ignore_changes** - Terraform will fight auto scaling
4. **Don't use very short cooldowns** - Causes flapping
5. **Don't enable too many policies** - Can conflict (pick CPU OR memory, not both for same aggressive targets)
6. **Don't forget cost limits** - Set max_capacity to control spend

---

## Advanced: Scheduled Scaling

For predictable traffic patterns:

```hcl
# Scale up for business hours (8 AM)
resource "aws_appautoscaling_scheduled_action" "scale_up_business_hours" {
  name               = "${var.env}-ecs-scale-up-business-hours"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  schedule           = "cron(0 8 * * MON-FRI *)"  # 8 AM weekdays (UTC)

  scalable_target_action {
    min_capacity = 3  # Start day with 3 tasks
    max_capacity = 10
  }
}

# Scale down after business hours (6 PM)
resource "aws_appautoscaling_scheduled_action" "scale_down_after_hours" {
  name               = "${var.env}-ecs-scale-down-after-hours"
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  schedule           = "cron(0 18 * * MON-FRI *)"  # 6 PM weekdays (UTC)

  scalable_target_action {
    min_capacity = 1  # Night time with 1 task
    max_capacity = 5
  }
}
```

---

## Quick Start Checklist

- [ ] Update `node_app_service.tf` - Add `desired_count` to `lifecycle.ignore_changes`
- [ ] Create `node_app_autoscaling.tf` - Configure auto scaling resources
- [ ] Run `terraform apply` - Deploy auto scaling configuration
- [ ] Monitor CloudWatch - Watch for scaling events over 24-48 hours
- [ ] Adjust parameters - Tune based on observed behavior
- [ ] Set up alarms - Alert when max capacity reached or scaling failures
- [ ] Document baseline - Record typical task counts for different times
- [ ] Load test - Verify scaling responds to traffic spikes

---

## Related Files

- **`node_app_service.tf`** - ECS service configuration
- **`node_app_autoscaling.tf`** - Auto scaling configuration (to be created)
- **`node_app_ecs_cluster.tf`** - ECS cluster with Container Insights
- **`ECS_TASK_RESTART_GUIDE.md`** - Deploying configuration updates

---

## Summary

**ECS Auto Scaling** automatically adjusts task count based on demand:

✅ **Target Tracking** - Recommended for most apps (CPU/Memory/Requests)
✅ **Min/Max Capacity** - Control costs and ensure availability  
✅ **Cooldown Periods** - Prevent flapping (5 min scale-in, 1 min scale-out)
✅ **Cost Savings** - 17-40% vs fixed capacity (depends on traffic pattern)
✅ **Zero Configuration After Setup** - Auto Scaling handles everything

**Recommended Starting Point:**
- Min: 1 task
- Max: 10 tasks
- Target: 70% CPU
- Scale-in cooldown: 300s
- Scale-out cooldown: 60s

Monitor for 1-2 weeks, then adjust based on actual usage! 📊

