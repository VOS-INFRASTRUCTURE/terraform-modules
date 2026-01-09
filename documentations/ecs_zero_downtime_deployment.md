# Zero-Downtime ECS Deployment Guide

## Overview

This guide explains how to achieve zero-downtime deployments with ECS Fargate using immutable image tags.

---

## 🤔 FAQ: How Zero-Downtime Actually Works

### Q1: Does the service auto-deploy when the task definition is updated?

**YES.** When you run `terraform apply` with a new image tag:

1. Terraform creates a **new task definition revision** (e.g., revision 5 → revision 6)
2. Terraform updates the **ECS service** to reference the new revision
3. ECS **automatically triggers a deployment** (no manual action needed)

You don't need to run `aws ecs update-service --force-new-deployment` manually.

---

### Q2: Does ECS auto-drain old tasks when new ones become healthy?

**YES, completely automatic.** ECS orchestrates the entire process:

1. ✅ Starts **new tasks** with new image
2. ⏳ Waits for **health checks to pass**
3. 🔄 Begins **draining connections** from old tasks
4. ❌ **Stops old tasks** after drain completes
5. 🧹 **Terminates** old tasks

No manual intervention required—ECS handles the entire lifecycle.

---

### Q3: Are we creating NEW tasks, not updating old ones?

**YES! You ALWAYS create new tasks, NEVER update existing ones.**

This is the foundation of **immutable infrastructure**:

❌ **Don't do this:**
- SSH into running tasks
- Update code in place
- Restart containers manually

✅ **Do this:**
- Create entirely new tasks with new image
- Let ECS route traffic to new tasks
- Let ECS terminate old tasks automatically

**Why immutability matters:**
- **Consistency**: All tasks run identical images (no drift)
- **Rollback**: Just deploy previous task definition revision
- **Debugging**: Old tasks are gone, can't have stale code
- **Auditability**: Every deployment is a distinct artifact

---

### Q4: Can you have TWO healthy tasks running at the same time?

**YES! That's the whole point of zero-downtime!**

With `desired_count = 1`:
- **Before deployment**: 1 old task running ✅
- **During deployment**: 1 old task + 1 new task = **2 tasks** ✅✅
- **After deployment**: 1 new task running ✅

**Timeline:**
```
t=0s:    [Old] ✅                        ← 1 task serving traffic
t=5s:    [Old] ✅  [New] ⏳              ← 2 tasks (new starting)
t=65s:   [Old] ✅  [New] ✅              ← 2 HEALTHY tasks (both serving)
t=66s:   [Old] 🔄  [New] ✅              ← Draining old
t=96s:   [New] ✅                        ← 1 task serving traffic
```

**Key insight:** You temporarily have **more than desired_count** during deployment. This is controlled by `deployment_maximum_percent = 200%`, which allows up to **2x** the desired count during rollouts.

**Result:** Traffic is ALWAYS served by at least 1 healthy task—true zero-downtime.

---

### Q5: What if my app takes a long time to start?

Adjust `health_check.startPeriod` to give your app enough time:

```hcl
healthCheck = {
  startPeriod = 120  # 2 minutes for slow startups
  interval    = 30
  retries     = 3
}
```

ECS will wait 120 seconds before enforcing health check failures, giving your app time to initialize.

---

### Q6: What happens if the new task fails health checks?

**ECS prevents bad deployments automatically:**

1. New task starts but fails health checks
2. ECS marks deployment as **failed**
3. ECS **keeps old tasks running** (no termination)
4. ECS **stops new tasks** (they never get traffic)
5. Your app continues serving on old, healthy tasks

**Manual action required:** Fix the issue, deploy again with a corrected image.

---

## ❌ Why `:latest` Breaks Zero-Downtime

### Problem
```hcl
image = "account.dkr.ecr.region.amazonaws.com/ecs-node-app:latest"
```

**Issues:**
1. **ECS doesn't auto-detect changes** - Task definition looks identical even when image content changes
2. **Requires manual force deployment** - `aws ecs update-service --force-new-deployment`
3. **No rollback capability** - Can't identify which "latest" was deployed when
4. **Race conditions** - Multiple deployments might pull different images with same tag
5. **No audit trail** - Can't correlate deployments to code commits

---

## ✅ Proper Zero-Downtime Strategy

### Use Immutable Tags

**Good examples:**
```
ecs-node-app:abc123f           # Git commit SHA (recommended)
ecs-node-app:v1.2.3            # Semantic version
ecs-node-app:build-456         # CI build number
ecs-node-app:2025-12-31-1430   # Timestamp
```

**How it works:**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. CI/CD Pipeline (GitHub Actions)                          │
│    - Build Docker image                                      │
│    - Tag with commit SHA: :abc123f                          │
│    - Push to ECR                                             │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Terraform Apply (with new tag)                           │
│    terraform apply -var="ecs_node_app_image_tag=abc123f"    │
│                                                              │
│    Creates NEW task definition revision (e.g., rev 5)       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. ECS Rolling Update                                        │
│    - Starts NEW tasks with :abc123f                         │
│    - Waits for health checks to pass                        │
│    - Routes traffic to new tasks                            │
│    - Drains OLD tasks with :xyz789a                         │
│    - Stops old tasks only when new ones healthy             │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Current Configuration

### Terraform Setup

**Variable** (`variables.tf`):
```hcl
variable "ecs_node_app_image_tag" {
  description = "Docker image tag (use commit SHA, NOT 'latest')"
  type        = string
  default     = "latest"  # Only for bootstrap
}
```

**Task Definition** (`node_app_task_definition.tf`):
```hcl
image = "${module.ecr_ecs_node_app.ecr_repository.url}:${var.ecs_node_app_image_tag}"
```

**Service Deployment Settings** (`node_app_service.tf`):
```hcl
deployment_minimum_healthy_percent = 50   # Can drop to 50% during deploy
deployment_maximum_percent         = 200  # Can scale to 200% during deploy
```

---

## 🚀 Deployment Workflow

### Initial Deploy (Bootstrap)

```bash
cd staging-infrastructure

# 1. Initialize Terraform
terraform init

# 2. First apply with default :latest
terraform apply

# 3. Build and push your first image
docker build -t ecs-node-app:v1.0.0 .
aws ecr get-login-password --region eu-west-2 | docker login --username AWS --password-stdin <account>.dkr.ecr.eu-west-2.amazonaws.com
docker tag ecs-node-app:v1.0.0 <account>.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:v1.0.0
docker push <account>.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:v1.0.0

# 4. Update to use real tag
terraform apply -var="ecs_node_app_image_tag=v1.0.0"
```

---

### Subsequent Deployments (Zero-Downtime)

```bash
# 1. Build new image with unique tag
docker build -t ecs-node-app:v1.1.0 .

# 2. Push to ECR
docker tag ecs-node-app:v1.1.0 <account>.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:v1.1.0
docker push <account>.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:v1.1.0

# 3. Deploy via Terraform
terraform apply -var="ecs_node_app_image_tag=v1.1.0"
```

**What happens:**
1. Terraform creates new task definition revision (e.g., rev 6)
2. ECS service update triggered
3. New tasks start with `:v1.1.0`
4. Health checks run for 60s (startPeriod)
5. ALB routes traffic to new tasks
6. Old tasks `:v1.0.0` drain connections
7. Old tasks stop after drain

**Timeline:**
- t=0s: New tasks start
- t=60s: Health checks begin passing
- t=65s: Traffic shifts to new tasks
- t=95s: Old tasks fully drained and stopped

**Zero downtime:** ✅ Old tasks keep serving until new ones healthy

---

### Rollback (Instant)

```bash
# Rollback to previous version
terraform apply -var="ecs_node_app_image_tag=v1.0.0"
```

ECS will:
1. Start tasks with old `:v1.0.0` image (already in ECR)
2. Wait for health checks
3. Drain and stop `:v1.1.0` tasks

---

## 🤖 CI/CD Integration (GitHub Actions)

### Recommended Workflow

**File:** `.github/workflows/deploy.yml`

```yaml
name: Deploy to ECS Staging

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-2

      - name: Login to ECR
        id: ecr-login
        run: |
          aws ecr get-login-password --region eu-west-2 | \
            docker login --username AWS --password-stdin \
            ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.eu-west-2.amazonaws.com

      - name: Build and push image
        env:
          ECR_REGISTRY: ${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.eu-west-2.amazonaws.com
          ECR_REPOSITORY: ecs-node-app
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
          docker push $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        working-directory: ./staging-infrastructure
        run: terraform init

      - name: Terraform Apply
        working-directory: ./staging-infrastructure
        env:
          TF_VAR_ecs_node_app_image_tag: ${{ github.sha }}
        run: terraform apply -auto-approve
```

**Key points:**
- Image tagged with `${{ github.sha }}` (commit SHA)
- Terraform gets tag via `TF_VAR_ecs_node_app_image_tag` env var
- Auto-apply after push to `main`

---

## 🔍 Monitoring Deployments

### Check Deployment Status

```bash
# Watch service events
aws ecs describe-services \
  --cluster ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].events[:5]'

# Watch running tasks
aws ecs list-tasks \
  --cluster ecs-node-app-cluster \
  --service staging-ecs-node-app-service

# Check task definition revision
aws ecs describe-services \
  --cluster ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].taskDefinition'
```

### CloudWatch Logs

```bash
# Stream logs from new tasks
aws logs tail /ecs/staging-ecs-node-app --follow
```

---

## ⚙️ Deployment Configuration

### Current Settings

| Setting | Value | Meaning |
|---------|-------|---------|
| `desired_count` | 1 | Number of tasks to run |
| `deployment_minimum_healthy_percent` | 50 | Can drop to 50% capacity during deploy |
| `deployment_maximum_percent` | 200 | Can scale to 200% capacity during deploy |
| `health_check.startPeriod` | 60s | Grace period before health checks enforce |
| `health_check.interval` | 30s | Check every 30 seconds |
| `health_check.retries` | 3 | 3 failures = unhealthy |

### Example Deployment Timeline

#### **With `desired_count = 1` (Current Config):**

```
t=0s:    [Task-A:v1.0.0] ✅                                ← Running (100%)
         Status: Serving traffic
         
         🚀 Deploy v1.1.0 triggered via Terraform
         
t=5s:    [Task-A:v1.0.0] ✅  [Task-B:v1.1.0] ⏳           ← Starting NEW task
         Status: Task-A serves traffic, Task-B provisioning
         Capacity: 200% (2 tasks, max allowed)
         
t=15s:   [Task-A:v1.0.0] ✅  [Task-B:v1.1.0] 🏥           ← Health checks running
         Status: Task-A serves traffic, Task-B being checked
         
t=60s:   [Task-A:v1.0.0] ✅  [Task-B:v1.1.0] 🏥           ← startPeriod ends
         Status: Health checks start enforcing pass/fail
         
t=65s:   [Task-A:v1.0.0] ✅  [Task-B:v1.1.0] ✅           ← NEW task HEALTHY
         Status: BOTH tasks healthy and serving traffic
         Capacity: 200% (temporary)
         
t=66s:   [Task-A:v1.0.0] 🔄  [Task-B:v1.1.0] ✅           ← Draining OLD task
         Status: Task-A draining connections, Task-B takes new traffic
         ECS Action: Stop sending new requests to Task-A
         
t=96s:   [Task-A:v1.0.0] ❌  [Task-B:v1.1.0] ✅           ← OLD task STOPPED
         Status: Task-A terminated, Task-B only task running
         Capacity: 100% (desired state restored)
```

**Key Point:** From t=0s to t=96s, you **ALWAYS have at least 1 healthy task** serving traffic. At peak (t=65s), you have **2 healthy tasks** running simultaneously.

---

#### **With `desired_count = 2`:**

```
t=0s:    [Task-A:v1.0.0] ✅  [Task-B:v1.0.0] ✅           ← Running (100%)
         Status: 2 tasks serving traffic
         
         🚀 Deploy v1.1.0 triggered
         
t=5s:    [Task-A:v1.0.0] ✅  [Task-B:v1.0.0] ✅  [Task-C:v1.1.0] ⏳  
         Status: Starting 1st new task
         Capacity: 150% (3 tasks)
         
t=65s:   [Task-A:v1.0.0] ✅  [Task-B:v1.0.0] ✅  [Task-C:v1.1.0] ✅  
         Status: 3 healthy tasks
         Capacity: 150%
         
t=66s:   [Task-A:v1.0.0] 🔄  [Task-B:v1.0.0] ✅  [Task-C:v1.1.0] ✅  
         Status: Draining Task-A
         
t=96s:   [Task-B:v1.0.0] ✅  [Task-C:v1.1.0] ✅  [Task-D:v1.1.0] ⏳  
         Status: Task-A stopped, starting 2nd new task
         Capacity: 150%
         
t=156s:  [Task-B:v1.0.0] ✅  [Task-C:v1.1.0] ✅  [Task-D:v1.1.0] ✅  
         Status: Task-D healthy
         
t=157s:  [Task-B:v1.0.0] 🔄  [Task-C:v1.1.0] ✅  [Task-D:v1.1.0] ✅  
         Status: Draining Task-B
         
t=187s:  [Task-C:v1.1.0] ✅  [Task-D:v1.1.0] ✅           ← Deployment complete
         Status: Only new tasks running
         Capacity: 100% (desired state)
```

**Zero downtime:** Always ≥1 healthy task serving traffic (actually ≥2 in this case)

---

## 🛡️ Best Practices

### ✅ DO

- **Use immutable tags** (commit SHA, semver)
- **Run health checks** on `/health` endpoint
- **Set appropriate `startPeriod`** (60s+ for slow startup apps)
- **Monitor CloudWatch Logs** during deployments
- **Test rollbacks** in staging first
- **Tag images in CI/CD** automatically

### ❌ DON'T

- **Never use `:latest`** for production deployments
- **Don't skip health checks** - they prevent bad deployments
- **Don't set `minimum_healthy_percent = 0`** - causes downtime
- **Don't deploy without monitoring** - watch logs for errors
- **Don't reuse tags** - breaks immutability and rollback

---

## 🚨 Troubleshooting

### Deployment Stuck / Tasks Failing

**Check task logs:**
```bash
aws logs tail /ecs/staging-ecs-node-app --follow
```

**Common issues:**
- Health check endpoint not returning 200
- App crashing on startup
- Insufficient memory/CPU
- Missing environment variables

**Quick fix:**
```bash
# Rollback to last known good version
terraform apply -var="ecs_node_app_image_tag=<previous-tag>"
```

### Service Not Updating

**Force new deployment:**
```bash
aws ecs update-service \
  --cluster ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

---

## 📊 Comparison: Manual vs. Automated

| Aspect | Manual (CLI) | Terraform + CI/CD |
|--------|--------------|-------------------|
| Image tagging | Manual | Automatic (commit SHA) |
| Task definition update | Manual JSON edits | Declarative HCL |
| Deployment trigger | Manual command | Git push |
| Rollback | Find old revision, redeploy | `terraform apply` with old tag |
| Audit trail | CloudTrail only | Git history + Terraform state |
| Consistency | Error-prone | Guaranteed |
| Zero-downtime | Manual orchestration | Automatic rolling update |

---

## ✅ Summary

**Current setup enables zero-downtime deployments via:**

1. **Immutable image tags** - Each deployment is a unique artifact
2. **Rolling updates** - New tasks start before old ones stop
3. **Health checks** - Traffic only routes to healthy tasks
4. **Declarative config** - Terraform manages state transitions
5. **Easy rollbacks** - Just deploy previous tag

**Next step:** Set up CI/CD pipeline to automate the build → tag → deploy flow!

