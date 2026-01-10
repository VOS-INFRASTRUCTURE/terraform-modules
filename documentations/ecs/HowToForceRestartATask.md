# How to Force Restart an ECS Task

## 📋 Table of Contents
- [Why Force Restart?](#why-force-restart)
- [Methods Overview](#methods-overview)
- [Method 1: Redeploy via GitHub Actions](#method-1-redeploy-via-github-actions-recommended)
- [Method 2: AWS Console](#method-2-aws-console)
- [Method 3: AWS CLI](#method-3-aws-cli)
- [Method 4: Terraform Force Replacement](#method-4-terraform-force-replacement)
- [Method 5: Update Service (Force New Deployment)](#method-5-update-service-force-new-deployment)
- [Task Types Comparison](#task-types-comparison)
- [Troubleshooting](#troubleshooting)

---

## 🎯 Why Force Restart?

Force restarting ECS tasks is necessary when:

- ✅ **New environment variables** added to Parameter Store/Secrets Manager
- ✅ **Configuration changes** that aren't picked up automatically
- ✅ **Debugging issues** (memory leaks, stuck processes)
- ✅ **Testing disaster recovery** procedures
- ✅ **Clearing application cache** stored in container memory
- ✅ **Applying security patches** without code changes

---

## 🔄 Methods Overview

| Method | Speed | Use Case | Builds New Image? | Best For |
|--------|-------|----------|-------------------|----------|
| **GitHub Actions Redeploy** | ⚡ 5-10 min | Code or config changes | ✅ Yes | Services & one-time tasks |
| **AWS Console** | ⚡⚡⚡ 30 sec | Quick restart | ❌ No | Emergency restarts |
| **AWS CLI** | ⚡⚡⚡ 10 sec | Automated scripts | ❌ No | CI/CD pipelines |
| **Terraform** | ⚡⚡ 2-5 min | Infrastructure changes | ❌ No | Planned maintenance |
| **Force New Deployment** | ⚡⚡⚡ 30 sec | Pick up new secrets/params | ❌ No | Config-only changes |

---

## Method 1: Redeploy via GitHub Actions (Recommended)

### 🎯 When to Use
- You've pushed new code
- You want to rebuild the Docker image
- You're deploying configuration changes
- You need to run migration tasks

### For ECS Services (e.g., Node.js API)

#### Step 1: Trigger Workflow Manually
```bash
# Option A: Make a trivial change and push
git commit --allow-empty -m "chore: force redeploy"
git push origin main

# Option B: Use GitHub UI
# Go to: Actions → Deploy ECS Node App → Run workflow → Select branch → Run
```

#### Step 2: What Happens Automatically
```
┌─────────────────────────────────────────────────────────────┐
│ 1. GitHub Actions Workflow Starts                            │
│    - Checks out code                                         │
│    - Builds Docker image with new tag (git SHA)              │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Push to ECR                                               │
│    - Pushes: <account>.dkr.ecr.eu-west-2.amazonaws.com/     │
│              ecs-node-app:<git-sha>                          │
│    - Updates: ecs-node-app:latest tag                        │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Update Task Definition                                    │
│    - Downloads current task definition                       │
│    - Replaces image with new SHA tag                         │
│    - Registers new task definition revision                  │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Deploy to ECS Service                                     │
│    - Updates service with new task definition                │
│    - Starts new tasks with new image                         │
│    - Waits for health checks to pass                         │
│    - Drains old tasks (zero-downtime deployment)             │
└─────────────────────────────────────────────────────────────┘
                        ↓
                  ✅ Deployment Complete
```

#### Example GitHub Workflow Excerpt
```yaml
# .github/workflows/deploy-ecs.yml
name: Deploy ECS Node App

on:
  push:
    branches: [main]
  workflow_dispatch:  # ← Allows manual trigger from GitHub UI

jobs:
  deploy:
    steps:
      - name: Build and push image
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:${{ github.sha }} .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:${{ github.sha }}
      
      - name: Deploy to ECS
        uses: aws-actions/amazon-ecs-deploy-task-definition@v2
        with:
          task-definition: ${{ steps.task-def.outputs.task-definition }}
          service: staging-ecs-node-app-service
          cluster: staging-ecs-node-app-cluster
          wait-for-service-stability: true  # Waits for new tasks to be healthy
```

---

### For One-Time Tasks (e.g., Database Migration)

#### Step 1: Trigger Migration Workflow
```bash
# Option A: GitHub UI
# Actions → Run Database Migration → Run workflow

# Option B: Via GitHub API
curl -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/your-org/your-repo/actions/workflows/migrate.yml/dispatches \
  -d '{"ref":"main"}'
```

#### Step 2: What Happens
```
┌─────────────────────────────────────────────────────────────┐
│ 1. Workflow Builds Migration Image                          │
│    - Builds: ecs-node-app-migrate:<git-sha>                  │
│    - Pushes to ECR                                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Run ECS Task (One-Time)                                   │
│    aws ecs run-task \                                        │
│      --cluster staging-ecs-node-app-cluster \                │
│      --task-definition staging-ecs-node-app-migrate-task \   │
│      --launch-type FARGATE \                                 │
│      --network-configuration "..."                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Wait for Task Completion                                  │
│    aws ecs wait tasks-stopped \                              │
│      --cluster staging-ecs-node-app-cluster \                │
│      --tasks <task-id>                                       │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Check Exit Code                                           │
│    - Exit 0 → ✅ Migration successful                        │
│    - Exit 1 → ❌ Migration failed (workflow fails)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Method 2: AWS Console

### 🎯 When to Use
- Emergency restart needed NOW
- No code changes, just restart
- Debugging live issues

### For ECS Services

#### Step-by-Step:
1. **Navigate to ECS**
   ```
   AWS Console → ECS → Clusters → staging-ecs-node-app-cluster
   ```

2. **Select Service**
   ```
   Click: staging-ecs-node-app-service
   ```

3. **Force New Deployment**
   ```
   Click: Update service
   ☑ Force new deployment (checkbox at top)
   Click: Update
   ```

4. **Monitor Progress**
   ```
   Events tab → Watch for:
   - "service has started 1 tasks"
   - "service has reached a steady state"
   ```

#### What This Does:
- Uses **existing task definition** (same image)
- Stops old tasks
- Starts new tasks with same configuration
- **Picks up new secrets/parameters** from Parameter Store/Secrets Manager

---

### For One-Time Tasks

#### Step-by-Step:
1. **Navigate to Task Definitions**
   ```
   AWS Console → ECS → Task Definitions → staging-ecs-node-app-migrate-task
   ```

2. **Run New Task**
   ```
   Click: Actions → Run task
   
   Configuration:
   - Launch type: Fargate
   - Cluster: staging-ecs-node-app-cluster
   - VPC: staging-vpc
   - Subnets: Select private subnets
   - Security group: Select appropriate SG
   
   Click: Run task
   ```

3. **Monitor Task**
   ```
   Tasks tab → Click task ID → Logs tab
   ```

---

## Method 3: AWS CLI

### 🎯 When to Use
- Automated scripts
- CI/CD pipelines outside GitHub
- Batch operations

### For ECS Services

```bash
# Force new deployment (restarts tasks with existing image)
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment \
  --region eu-west-2

# Wait for stability
aws ecs wait services-stable \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --region eu-west-2

echo "✅ Service restarted successfully"
```

---

### For One-Time Tasks

```bash
#!/bin/bash
# run-migration.sh

CLUSTER="staging-ecs-node-app-cluster"
TASK_DEF="staging-ecs-node-app-migrate-task"
REGION="eu-west-2"

# Get VPC configuration (adjust subnet/security group IDs)
SUBNET_IDS="subnet-xxxxx,subnet-yyyyy"  # Your private subnets
SECURITY_GROUP="sg-zzzzz"  # Your security group

# Run task
TASK_ARN=$(aws ecs run-task \
  --cluster $CLUSTER \
  --task-definition $TASK_DEF \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={
    subnets=[$SUBNET_IDS],
    securityGroups=[$SECURITY_GROUP],
    assignPublicIp=DISABLED
  }" \
  --region $REGION \
  --query 'tasks[0].taskArn' \
  --output text)

echo "🚀 Started task: $TASK_ARN"

# Wait for completion
aws ecs wait tasks-stopped \
  --cluster $CLUSTER \
  --tasks $TASK_ARN \
  --region $REGION

# Check exit code
EXIT_CODE=$(aws ecs describe-tasks \
  --cluster $CLUSTER \
  --tasks $TASK_ARN \
  --region $REGION \
  --query 'tasks[0].containers[0].exitCode' \
  --output text)

if [ "$EXIT_CODE" -eq 0 ]; then
  echo "✅ Migration completed successfully"
  exit 0
else
  echo "❌ Migration failed with exit code: $EXIT_CODE"
  exit 1
fi
```

**Make it executable:**
```bash
chmod +x run-migration.sh
./run-migration.sh
```

---

## Method 4: Terraform Force Replacement

### 🎯 When to Use
- Infrastructure changes
- Task definition updates
- Planned maintenance windows

### Force Replace Service

```bash
# Option A: Force replace the entire service
terraform taint module.infrastructure.aws_ecs_service.node_app_service
terraform apply

# Option B: Targeted replacement (Terraform 1.5+)
terraform apply -replace="module.infrastructure.aws_ecs_service.node_app_service"
```

⚠️ **Warning**: This recreates the service (brief downtime possible).

---

### Force Replace Task Definition

```bash
# Trigger task definition update by changing a tag or description
# Edit staging-infrastructure/node_app_task_definition.tf.bak

resource "aws_ecs_task_definition" "node_app" {
  # ...existing code...
  
  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
    Version     = "2.0"  # ← Change this to force update
  }
}
```

Then apply:
```bash
terraform apply
```

The service will automatically deploy the new task definition revision.

---

## Method 5: Update Service (Force New Deployment)

### 🎯 When to Use
- New secrets/parameters added
- No code or infrastructure changes
- Fastest restart method

### Using AWS CLI

```bash
# This is the FASTEST way to restart tasks
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment \
  --region eu-west-2
```

**Time to Complete**: ~30-60 seconds

**What It Does**:
- Stops old tasks
- Starts new tasks with **same task definition**
- Fetches **latest values** from Parameter Store/Secrets Manager
- Zero-downtime (new tasks healthy before old ones stop)

---

## 📊 Task Types Comparison

### ECS Service vs. One-Time Task

| Aspect | ECS Service | One-Time Task (e.g., Migration) |
|--------|-------------|----------------------------------|
| **Purpose** | Long-running application | Short-lived job |
| **Restart Behavior** | Auto-restarts on failure | Runs once, exits |
| **How to Restart** | Update service / Force new deployment | Run new task manually |
| **GitHub Workflow** | Deploys to service | Runs task, waits for completion |
| **Desired Count** | Maintains count (e.g., 1 or 2) | N/A (runs 1 task) |
| **Load Balancer** | ✅ Usually attached | ❌ Not attached |
| **Use Case** | API servers, web apps | Database migrations, data imports |

---

## 🛠️ Troubleshooting

### Issue: Service Stuck in "Deployment Failed"

**Cause**: Health checks failing

**Solution**:
```bash
# Check logs
aws logs tail /aws/ecs/staging-ecs-node-app --follow

# Check service events
aws ecs describe-services \
  --cluster staging-ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].events[0:5]'
```

---

### Issue: Task Immediately Stops

**Cause**: Container crashes on startup

**Solution**:
```bash
# Get stopped task ID
TASK_ID=$(aws ecs list-tasks \
  --cluster staging-ecs-node-app-cluster \
  --desired-status STOPPED \
  --query 'taskArns[0]' \
  --output text)

# Check exit code and reason
aws ecs describe-tasks \
  --cluster staging-ecs-node-app-cluster \
  --tasks $TASK_ID \
  --query 'tasks[0].{ExitCode:containers[0].exitCode,Reason:stoppedReason}'
```

---

### Issue: New Environment Variables Not Picked Up

**Cause**: Task using cached values

**Solution**:
```bash
# Force new deployment to fetch latest values
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment \
  --region eu-west-2
```

**Note**: Environment variables from Parameter Store/Secrets Manager are fetched at **task startup**, not from running container.

---

### Issue: GitHub Workflow Fails at "Deploy" Step

**Cause**: IAM permissions missing

**Solution**: Check IAM user `staging-github-actions-ecs-deploy` has:
```json
{
  "Effect": "Allow",
  "Action": [
    "ecs:UpdateService",
    "ecs:RegisterTaskDefinition",
    "ecs:DescribeServices",
    "ecs:RunTask",
    "iam:PassRole"
  ],
  "Resource": "*"
}
```

---

## 📌 Quick Reference

### Fastest Restart Methods

```bash
# 1. For ECS Service (30 seconds)
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment \
  --region eu-west-2

# 2. For One-Time Task (immediate)
aws ecs run-task \
  --cluster staging-ecs-node-app-cluster \
  --task-definition staging-ecs-node-app-migrate-task:latest \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-xxx],securityGroups=[sg-yyy]}" \
  --region eu-west-2
```

---

## 🔗 Related Documentation
- [ECS Auto Scaling Guide](ECSAutoScaling.md)
- [ECS Task Usage Guide](ECSTaskUsage.md)
- [Parameter Store vs Secrets Manager](ParamStoreVsSecretsManager.md)
- [GitHub Actions Workflows](../../.github/workflows/)

---

**Last Updated**: January 2026  
**Maintained By**: Infrastructure Team

