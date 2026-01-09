# ECS Task Restart Guide - Applying Configuration Updates

## Quick Reference

When you update SSM Parameter Store or Secrets Manager values, **existing containers DO NOT automatically reload** the new values. You must force a restart to inject the updated configurations.

---

## ⚡ Quick Commands

### Recommended: Force New Deployment (Zero Downtime)

```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

**Use this when:**
- ✅ You updated SSM Parameter Store values
- ✅ You rotated Secrets Manager secrets
- ✅ You want zero downtime
- ✅ You need a clean rolling deployment

---

## Detailed Methods

### Method 1: Re-run GitHub Actions Workflow ⭐ EASIEST

**Step-by-Step:**

1. **Navigate to GitHub Actions**
   ```
   https://github.com/<your-org>/<your-repo>/actions
   ```

2. **Find the workflow**
   - Look for "Deploy ECS Node App" (or your workflow name)
   - Find the last successful run on your branch (e.g., `no-merge-ecs`)

3. **Trigger re-run**
   - Click on the workflow run
   - Click **"Re-run all jobs"** button (top-right)
   - Confirm the re-run

4. **Monitor progress**
   - Watch the workflow logs in real-time
   - Typical stages:
     ```
     ✓ Checkout code
     ✓ Configure AWS credentials
     ✓ Login to Amazon ECR
     ✓ Build Docker image
     ✓ Push to ECR (new tag = commit SHA)
     ✓ Update ECS task definition
     ✓ Deploy to ECS service
     ✓ Wait for service stability
     ```

**What Happens Behind the Scenes:**

```
1. GitHub Actions starts workflow
   ↓
2. Builds Docker image from current code
   ↓
3. Tags image with commit SHA (e.g., 0342c14a991591...)
   ↓
4. Pushes to ECR: 820242908282.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:0342c14a991591...
   ↓
5. Downloads current ECS task definition
   ↓
6. Updates task definition with new image tag
   ↓
7. Registers new task definition revision
   ↓
8. Updates ECS service to use new revision
   ↓
9. ECS starts new tasks (rolling deployment)
   ↓
10. New tasks fetch LATEST configs from SSM/Secrets Manager ✅
   ↓
11. Health checks pass
   ↓
12. ALB routes traffic to new tasks
   ↓
13. Old tasks drained and stopped
```

**Timeline:**
```
t=0s:     Workflow triggered
t=30s:    Build starts
t=2min:   Docker image built
t=3min:   Image pushed to ECR
t=3.5min: Task definition updated
t=4min:   ECS deployment starts
t=5min:   New tasks running health checks
t=6min:   New tasks healthy
t=6.5min: Traffic routed to new tasks
t=7min:   Old tasks stopped
DONE:     Deployment complete!
```

**Characteristics:**
- ⏱️ Duration: 3-7 minutes (includes build time)
- 🔄 Downtime: **ZERO**
- 💰 Cost: No extra cost (just normal ECS charges)
- 🎯 Use case: **PRIMARY METHOD** for config updates
- 📝 Audit: Full logs in GitHub Actions

**Advantages over AWS CLI:**
- ✅ No local AWS credentials needed
- ✅ Works from anywhere (even mobile browser)
- ✅ Consistent with normal deployment flow
- ✅ Creates new image tag (better versioning)
- ✅ Full visibility in GitHub UI
- ✅ Can be triggered by team members without AWS access
- ✅ Automatically documented in GitHub Actions history

**Example Scenario:**

```bash
# 1. Update SSM parameter
aws ssm put-parameter \
  --name "/staging/node-app/config/log_level" \
  --value "debug" \
  --overwrite

# 2. Instead of running AWS CLI commands, just:
#    - Open GitHub → Actions
#    - Click "Re-run all jobs"
#    - Wait 5-7 minutes
#    - Done! New containers have LOG_LEVEL=debug
```

---

### Method 2: Force New Deployment via AWS CLI ⭐ RECOMMENDED

**Command:**
```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

**What Happens:**
```
1. ECS starts NEW tasks (desired count × 2 temporarily)
2. New tasks fetch LATEST values from SSM/Secrets Manager
3. Health checks run on new tasks
4. ALB starts routing traffic to new tasks
5. Old tasks receive SIGTERM (graceful shutdown)
6. Old tasks drain connections (deregistration_delay = 30s)
7. Old tasks are stopped
8. Cluster returns to normal task count
```

**Timeline:**
```
t=0s:    Force deployment triggered
t=10s:   New tasks starting
t=30s:   New tasks running health checks
t=60s:   New tasks marked healthy
t=65s:   ALB routes traffic to new tasks
t=95s:   Old tasks drained and stopped
DONE:    All containers running with new configs
```

**Characteristics:**
- ⏱️ Duration: 2-5 minutes
- 🔄 Downtime: **ZERO** (if minimum_healthy_percent ≥ 100)
- 💰 Cost: Brief spike (double task count for ~1 minute)
- 🎯 Use case: Production deployments

**Monitoring:**
```bash
# Watch deployment progress
aws ecs describe-services \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].deployments'

# Check if deployment complete
aws ecs wait services-stable \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service

echo "Deployment complete!"
```

---

### Method 2: Stop Individual Tasks

**List Running Tasks:**
```bash
aws ecs list-tasks \
  --cluster staging-ecs-node-app-cluster \
  --service-name staging-ecs-node-app-service \
  --query 'taskArns[]' \
  --output text
```

**Stop One Task:**
```bash
aws ecs stop-task \
  --cluster staging-ecs-node-app-cluster \
  --task <task-id-from-above>
```

**What Happens:**
```
1. You manually stop task-1
2. ECS immediately starts task-2 (to maintain desired count)
3. Task-2 fetches latest configs from SSM/Secrets Manager
4. Task-2 becomes healthy
5. ALB routes traffic to task-2
6. Repeat for other tasks if multiple
```

**Characteristics:**
- ⏱️ Duration: 1-3 minutes per task
- 🔄 Downtime: Brief (if only 1 task); none if multiple
- 💰 Cost: No extra cost
- 🎯 Use case: Testing, gradual rollout, debugging

**Example - Rolling Restart of All Tasks:**
```bash
#!/bin/bash
CLUSTER="staging-ecs-node-app-cluster"
SERVICE="staging-ecs-node-app-service"

# Get all task IDs
TASKS=$(aws ecs list-tasks \
  --cluster $CLUSTER \
  --service-name $SERVICE \
  --query 'taskArns[]' \
  --output text)

# Stop each task one by one
for TASK in $TASKS; do
  echo "Stopping task: $TASK"
  aws ecs stop-task --cluster $CLUSTER --task $TASK
  
  # Wait for new task to be healthy before stopping next one
  echo "Waiting 2 minutes for replacement task to start..."
  sleep 120
done

echo "All tasks restarted!"
```

---

### Method 3: Scale Down Then Up ⚠️ CAUSES DOWNTIME

**Scale to Zero:**
```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --desired-count 0
```

**Wait for Tasks to Stop:**
```bash
# Check until no tasks running
while [ $(aws ecs list-tasks \
  --cluster staging-ecs-node-app-cluster \
  --service-name staging-ecs-node-app-service \
  --query 'length(taskArns)') -gt 0 ]; do
  echo "Waiting for tasks to stop..."
  sleep 5
done

echo "All tasks stopped"
```

**Scale Back Up:**
```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --desired-count 1  # Or your normal count
```

**Characteristics:**
- ⏱️ Duration: 1-2 minutes
- 🔄 Downtime: **YES!** (30-60 seconds)
- 💰 Cost: Saves money during downtime window
- 🎯 Use case: Scheduled maintenance, cost-sensitive dev environments

**⚠️ WARNING:** Service will be completely DOWN during this process!

---

### Method 4: Update Task Definition Revision

**Download Current Task Definition:**
```bash
aws ecs describe-task-definition \
  --task-definition staging-ecs-node-app-task \
  --query 'taskDefinition' \
  > task-definition.json
```

**Register New Revision (Even With Same Config):**
```bash
# Remove fields that can't be re-registered
jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' \
  task-definition.json > task-definition-clean.json

# Register new revision
aws ecs register-task-definition \
  --cli-input-json file://task-definition-clean.json
```

**Update Service to New Revision:**
```bash
# Get new revision number
NEW_REVISION=$(aws ecs describe-task-definition \
  --task-definition staging-ecs-node-app-task \
  --query 'taskDefinition.revision' \
  --output text)

# Update service
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --task-definition staging-ecs-node-app-task:$NEW_REVISION
```

**Characteristics:**
- ⏱️ Duration: 2-5 minutes
- 🔄 Downtime: **ZERO**
- 💰 Cost: Brief spike (double task count)
- 🎯 Use case: Image updates, config changes, rollbacks

**Use for Rollback:**
```bash
# Rollback to previous revision
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --task-definition staging-ecs-node-app-task:PREVIOUS_REVISION_NUMBER
```

---

### Method 5: Via Terraform

**Temporarily Disable Lifecycle Rule:**

Edit `node_app_task_definition.tf`:

```hcl
# Comment out lifecycle block:
# lifecycle {
#   ignore_changes = [container_definitions]
# }
```

**Apply Changes:**
```bash
terraform apply
```

**What Happens:**
```
1. Terraform detects changes to task definition
2. New revision created automatically
3. Service updated to new revision
4. Rolling deployment starts (same as Method 1)
```

**Re-enable Lifecycle Rule After:**
```hcl
# Uncomment lifecycle block:
lifecycle {
  ignore_changes = [container_definitions]
}
```

**Characteristics:**
- ⏱️ Duration: 2-5 minutes
- 🔄 Downtime: **ZERO**
- 💰 Cost: Brief spike
- 🎯 Use case: Infrastructure changes, systematic updates

---

## Common Scenarios

### Scenario 1: Updated SSM Parameter Store Value

**Example:** Changed `LOG_LEVEL` from `info` to `debug`

```bash
# Step 1: Update parameter
aws ssm put-parameter \
  --name "/staging/node-app/config/log_level" \
  --value "debug" \
  --overwrite

# Step 2: Force new deployment
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment

# Step 3: Verify new tasks have updated config
aws ecs describe-tasks \
  --cluster staging-ecs-node-app-cluster \
  --tasks $(aws ecs list-tasks \
    --cluster staging-ecs-node-app-cluster \
    --service-name staging-ecs-node-app-service \
    --query 'taskArns[0]' \
    --output text) \
  --query 'tasks[0].createdAt'

# Step 4: Check logs to confirm debug level active
aws logs tail /ecs/staging-ecs-node-app --follow
```

---

### Scenario 2: Rotated Database Password

**Example:** Password changed in Secrets Manager

```bash
# Step 1: Update secret (already done via rotation or manual update)

# Step 2: Force new deployment
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment

# Step 3: Monitor for database connection errors
aws logs filter-pattern "database" \
  --log-group-name /ecs/staging-ecs-node-app \
  --start-time $(date -u -d '5 minutes ago' +%s)000
```

---

### Scenario 3: Multiple Config Changes at Once

**Example:** Updated 3 parameters and 1 secret

```bash
# Update all configs first (no restarts yet)
aws ssm put-parameter --name "/staging/node-app/config/port" --value "8080" --overwrite
aws ssm put-parameter --name "/staging/node-app/config/log_level" --value "warn" --overwrite
aws ssm put-parameter --name "/staging/node-app/features/enable_cors" --value "false" --overwrite
aws secretsmanager put-secret-value --secret-id staging/node-app/database/credentials --secret-string '{"username":"newuser","password":"newpass"}'

# Single deployment picks up ALL changes
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

---

## Verification & Troubleshooting

### Verify Deployment Success

```bash
# Check deployment status
aws ecs describe-services \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].deployments[?status==`PRIMARY`]'

# Should show:
# - desiredCount: 1 (or your count)
# - runningCount: 1
# - status: PRIMARY
```

### Check Task Health

```bash
# Get task details
aws ecs describe-tasks \
  --cluster staging-ecs-node-app-cluster \
  --tasks $(aws ecs list-tasks \
    --cluster staging-ecs-node-app-cluster \
    --service-name staging-ecs-node-app-service \
    --query 'taskArns[0]' \
    --output text) \
  --query 'tasks[0].{Health:healthStatus,Status:lastStatus,StartedAt:startedAt}'
```

### View Container Logs

```bash
# Tail logs from new containers
aws logs tail /ecs/staging-ecs-node-app --follow

# Filter for startup messages
aws logs filter-pattern "Server running" \
  --log-group-name /ecs/staging-ecs-node-app \
  --start-time $(date -u -d '5 minutes ago' +%s)000
```

### Check Environment Variables (Inside Container)

```bash
# Execute command in running container (requires ECS Exec enabled)
aws ecs execute-command \
  --cluster staging-ecs-node-app-cluster \
  --task <task-id> \
  --container ecs-node-app-container \
  --interactive \
  --command "env | grep -E '(PORT|LOG_LEVEL|DB_)'"
```

---

## Best Practices

### ✅ DO

1. **Use Method 1 for production** - Zero downtime, clean rollout
2. **Batch config updates** - Change multiple configs, then deploy once
3. **Monitor during deployment** - Watch CloudWatch Logs for errors
4. **Set proper health checks** - Ensures new tasks are truly ready
5. **Configure ALB deregistration delay** - Allows graceful connection draining (30-60s)
6. **Test in staging first** - Verify config changes before production

### ❌ DON'T

1. **Don't use scale-down method in production** - Causes downtime
2. **Don't skip monitoring** - Always watch logs during deployment
3. **Don't change too many configs at once** - Hard to debug if something breaks
4. **Don't forget to verify** - Check that new values are actually injected
5. **Don't restart during peak traffic** - Schedule updates during low-traffic periods

---

## Automation Scripts

### One-Command Update & Deploy

```bash
#!/bin/bash
# File: update-config-and-deploy.sh

CONFIG_NAME=$1
CONFIG_VALUE=$2

if [ -z "$CONFIG_NAME" ] || [ -z "$CONFIG_VALUE" ]; then
  echo "Usage: $0 <config-name> <config-value>"
  echo "Example: $0 log_level debug"
  exit 1
fi

CLUSTER="staging-ecs-node-app-cluster"
SERVICE="staging-ecs-node-app-service"
PARAM_PATH="/staging/node-app/config/$CONFIG_NAME"

echo "Updating $PARAM_PATH to $CONFIG_VALUE..."
aws ssm put-parameter \
  --name "$PARAM_PATH" \
  --value "$CONFIG_VALUE" \
  --overwrite

echo "Forcing new deployment..."
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --force-new-deployment \
  --no-cli-pager

echo "Waiting for deployment to stabilize..."
aws ecs wait services-stable \
  --cluster $CLUSTER \
  --services $SERVICE

echo "Deployment complete! Checking logs..."
aws logs tail /ecs/staging-ecs-node-app --since 2m
```

**Usage:**
```bash
chmod +x update-config-and-deploy.sh
./update-config-and-deploy.sh log_level debug
```

---

## Summary Table

| Method | Downtime | Duration | Cost | Use Case |
|--------|----------|----------|------|----------|
| **GitHub Actions Re-run** | None | 3-7 min | None | ✅ PRIMARY - Config updates, easiest |
| **Force New Deployment (CLI)** | None | 2-5 min | Brief spike | Alternative if GitHub unavailable |
| **Stop Individual Tasks** | Minimal | 1-3 min/task | None | Testing, gradual rollout |
| **Scale Down/Up** | Yes! | 1-2 min | Saves $ | Scheduled maintenance |
| **New Task Definition** | None | 2-5 min | Brief spike | Image updates, rollbacks |
| **Via Terraform** | None | 2-5 min | Brief spike | Infrastructure changes |

**Recommendation:** Use **GitHub Actions Re-run (Method 1)** for 99% of cases when updating configs. It's the simplest, most visible, and doesn't require AWS CLI access.

