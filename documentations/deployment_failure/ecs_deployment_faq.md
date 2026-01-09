# Quick Reference: ECS Deployment Questions Answered

## Your Questions, Definitively Answered

### ❓ Q: Does the service auto-deploy when task definition is updated?

✅ **YES**

When you run:
```bash
terraform apply -var="ecs_node_app_image_tag=v1.1.0"
```

Terraform automatically:
1. Creates new task definition revision
2. Updates ECS service to use new revision
3. **ECS triggers deployment automatically** (no manual force-deploy needed)

---

### ❓ Q: Does ECS auto-drain old tasks when new ones become healthy?

✅ **YES, completely automatic**

ECS orchestrates:
1. Start new tasks
2. Wait for health checks to pass
3. **Auto-drain old tasks** (stop new requests, finish existing connections)
4. Stop old tasks after drain completes

You don't have to do anything manually.

---

### ❓ Q: Are we creating NEW tasks, not updating old ones?

✅ **YES, always NEW tasks**

**Immutable infrastructure:**
- ❌ Don't update: No SSH, no in-place updates
- ✅ Create new: Entirely new tasks with new image
- ✅ Destroy old: Terminate old tasks after new ones healthy

**Why?**
- Consistency (no drift)
- Easy rollback (deploy old revision)
- Auditability (each deploy is distinct artifact)

---

### ❓ Q: Can you have TWO healthy tasks at the same time?

✅ **YES! That's how zero-downtime works**

**With `desired_count = 1`:**

```
Before:  [Old v1.0.0] ✅                    ← 1 task
During:  [Old v1.0.0] ✅  [New v1.1.0] ✅   ← 2 tasks (BOTH healthy!)
After:   [New v1.1.0] ✅                    ← 1 task
```

**Key insight:** You temporarily have **MORE than desired_count** during deployment.

**Why this works:**
- `deployment_maximum_percent = 200%` allows up to 2x desired count
- At t=65s, you have 2 healthy tasks serving traffic
- Old task drains and stops only after new task is healthy
- **Result: Always ≥1 healthy task serving traffic = zero downtime**

---

## The Magic Moment

**The critical moment that guarantees zero-downtime:**

```
t=65s:   [Task-A:v1.0.0] ✅  [Task-B:v1.1.0] ✅

         ↑                    ↑
         Old task             New task
         (still healthy)      (now healthy!)
         
         BOTH serving traffic simultaneously
```

Before ECS stops Task-A, it:
1. ✅ Confirms Task-B is healthy
2. 🔄 Drains Task-A (finish existing connections)
3. ❌ Stops Task-A only after drain completes

**You NEVER have zero healthy tasks.**

---

## Visual Timeline

```
Deployment Timeline (desired_count = 1):

t=0s    [Old] ✅ ────────────────────────────────────────┐
                                                          │ Old task
t=5s    [Old] ✅ ───────┐                                 │ serves traffic
        [New] ⏳        │ New task starting               │
                        │                                 │
t=65s   [Old] ✅ ───────┤ BOTH HEALTHY!                  │
        [New] ✅        │ (zero-downtime guaranteed)      │
                        │                                 │
t=66s   [Old] 🔄 ───────┤ Draining old task              │
        [New] ✅        │                                 │
                        │                                 ↓
t=96s   [New] ✅ ───────┴─────────────────────────────────
        
        Old task terminated ❌

Legend:
✅ = Healthy & serving traffic
⏳ = Starting (not serving traffic yet)
🔄 = Draining (existing connections only, no new requests)
❌ = Stopped/terminated
```

---

## Common Misconceptions

### ❌ Misconception: Task is updated in-place
**Reality:** New task is created, old task is terminated

### ❌ Misconception: Old task stops immediately when new task starts
**Reality:** Old task keeps running until new task is healthy

### ❌ Misconception: You can never have more tasks than desired_count
**Reality:** During deployment, you can have up to `deployment_maximum_percent` (200% = 2x)

### ❌ Misconception: You need to manually route traffic
**Reality:** ECS (+ ALB if using one) handles traffic routing automatically

### ❌ Misconception: Deployment requires manual force-deploy
**Reality:** Terraform updating the service triggers deployment automatically

---

## Key Configuration

**Why you get zero-downtime with these settings:**

```hcl
# Allows 2x tasks during deployment
deployment_maximum_percent = 200

# Never drop below 50% capacity (1 task minimum with desired_count=1)
deployment_minimum_healthy_percent = 50

# Health check grace period (app startup time)
health_check.startPeriod = 60s
```

**Formula:**
- Max tasks during deploy: `desired_count × (deployment_maximum_percent / 100)`
  - Example: 1 × (200 / 100) = **2 tasks**
  
- Min tasks during deploy: `desired_count × (deployment_minimum_healthy_percent / 100)`
  - Example: 1 × (50 / 100) = **0.5 → rounds to 1 task**

**Result:** You can run 1-2 tasks during deployment, guaranteeing no downtime.

---

## Deployment Safety

**What happens if deployment fails?**

```
Scenario: New task fails health checks

[Old v1.0.0] ✅  [New v1.1.0] ❌ (unhealthy)
     ↓                  ↓
Keeps running      ECS stops it (never gets traffic)

Result:
✅ Old task continues serving traffic
❌ Deployment marked as FAILED
🔄 Manual action: Fix bug, redeploy
```

**ECS prevents bad deployments from taking down your service.**

---

## Real-World Example

**Deploy flow:**

```bash
# 1. Build new image
docker build -t app:abc123f .

# 2. Push to ECR
docker push 168000258763.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:abc123f

# 3. Deploy via Terraform
terraform apply -var="ecs_node_app_image_tag=abc123f"

# What happens automatically:
# - New task definition created (revision 6)
# - Service updated to use revision 6
# - ECS starts new task with :abc123f
# - Health checks pass
# - Old task drains and stops
# - Deployment complete

# Result: Zero downtime, no manual intervention
```

---

## Summary

**To answer your questions directly:**

1. ✅ **Service auto-deploys** when task definition is updated (via Terraform)
2. ✅ **ECS auto-drains** old tasks when new ones become healthy
3. ✅ **New tasks are created**, old tasks are terminated (not updated in-place)
4. ✅ **Two healthy tasks CAN run simultaneously** (during deployment, briefly)

**This is how zero-downtime is achieved!**

---

## Learn More

See detailed documentation:
- `ecs_zero_downtime_deployment.md` - Complete deployment guide
- `ecs_rolling_deployment_visualized.md` - Visual step-by-step breakdown

