# ECS Rolling Deployment Visualized

## The Complete Picture: How ECS Achieves Zero-Downtime

This document shows **exactly** what happens during a deployment, task by task, second by second.

---

## Scenario: Deploying v1.1.0 to Replace v1.0.0

**Current state:**
- Service: `staging-ecs-node-app-service`
- Desired count: 1
- Running task: `Task-A` with image `:v1.0.0`

**Action:** Deploy new image `:v1.1.0` via Terraform

---

## Step-by-Step Deployment Flow

### **Phase 1: Pre-Deployment (Stable State)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Desired: 1 task                                        │
│  Running: 1 task                                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐                               │
│  │  Task-A (v1.0.0)     │  ✅ HEALTHY                   │
│  │  IP: 10.1.1.50       │                               │
│  │  Status: RUNNING     │  Serving 100% of traffic      │
│  └──────────────────────┘                               │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 100% (1 of 1 desired tasks)
🚦 Traffic: All requests → Task-A
```

---

### **Phase 2: Terraform Apply (Task Definition Updated)**

```bash
$ terraform apply -var="ecs_node_app_image_tag=v1.1.0"

# Terraform actions:
1. Creates NEW task definition revision
   - Old: staging-ecs-node-app-task:5
   - New: staging-ecs-node-app-task:6

2. Updates ECS service to use revision 6

3. ECS detects change → triggers deployment
```

---

### **Phase 3: New Task Starting (t=5s)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Desired: 1 task                                        │
│  Running: 2 tasks (during deployment)                   │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Task-A (v1.0.0)     │  │  Task-B (v1.1.0)     │    │
│  │  IP: 10.1.1.50       │  │  IP: 10.1.1.51       │    │
│  │  Status: RUNNING     │  │  Status: PROVISIONING│    │
│  │  ✅ HEALTHY          │  │  ⏳ STARTING         │    │
│  └──────────────────────┘  └──────────────────────┘    │
│         ↑                           ↑                   │
│         │                           │                   │
│    Serving traffic          Pulling image from ECR     │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 200% (2 of 1 desired tasks - max allowed)
🚦 Traffic: All requests → Task-A (only healthy task)
⏱️  ECS Action: Provisioning Task-B
```

---

### **Phase 4: Health Checks Running (t=15s - t=60s)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Running: 2 tasks                                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Task-A (v1.0.0)     │  │  Task-B (v1.1.0)     │    │
│  │  IP: 10.1.1.50       │  │  IP: 10.1.1.51       │    │
│  │  Status: RUNNING     │  │  Status: RUNNING     │    │
│  │  ✅ HEALTHY          │  │  🏥 HEALTH CHECKING  │    │
│  └──────────────────────┘  └──────────────────────┘    │
│         ↑                           ↑                   │
│         │                           │                   │
│    Serving traffic          Health check:              │
│                             GET http://10.1.1.51:3000/health
│                             startPeriod: 0-60s (grace)  │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 200%
🚦 Traffic: All requests → Task-A
⏱️  ECS Action: Monitoring Task-B health
🏥 Health Check: Every 30s (not enforced yet due to startPeriod)
```

---

### **Phase 5: New Task Healthy (t=65s)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Running: 2 tasks                                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Task-A (v1.0.0)     │  │  Task-B (v1.1.0)     │    │
│  │  IP: 10.1.1.50       │  │  IP: 10.1.1.51       │    │
│  │  Status: RUNNING     │  │  Status: RUNNING     │    │
│  │  ✅ HEALTHY          │  │  ✅ HEALTHY          │    │
│  └──────────────────────┘  └──────────────────────┘    │
│         ↑                           ↑                   │
│         │                           │                   │
│    Serving traffic          Now serving traffic too!   │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 200% (2 healthy tasks)
🚦 Traffic: Requests → BOTH Task-A and Task-B
⏱️  ECS Action: Preparing to drain Task-A
✅ CRITICAL MOMENT: You now have 2 healthy tasks serving traffic!
```

**This is the key to zero-downtime:** Both old and new tasks are healthy and serving traffic simultaneously before the old task is stopped.

---

### **Phase 6: Draining Old Task (t=66s - t=96s)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Running: 2 tasks (draining old)                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Task-A (v1.0.0)     │  │  Task-B (v1.1.0)     │    │
│  │  IP: 10.1.1.50       │  │  IP: 10.1.1.51       │    │
│  │  Status: DRAINING    │  │  Status: RUNNING     │    │
│  │  🔄 DRAINING         │  │  ✅ HEALTHY          │    │
│  └──────────────────────┘  └──────────────────────┘    │
│         ↑                           ↑                   │
│         │                           │                   │
│   Finishing existing       Receiving ALL new            │
│   connections only         requests                     │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 200% → 100% (transitioning)
🚦 Traffic:
    - New requests → Task-B only
    - Existing connections on Task-A → allowed to finish
⏱️  ECS Action: Waiting for Task-A connections to drain (30s default)
🔄 Drain Period: Active connections finish gracefully
```

**What "draining" means:**
- ECS removes Task-A from load balancer target group (if using ALB)
- No NEW requests sent to Task-A
- EXISTING connections allowed to complete (up to 30s)
- Task keeps running until drain completes

---

### **Phase 7: Old Task Stopped (t=96s)**

```
┌─────────────────────────────────────────────────────────┐
│  ECS Service: staging-ecs-node-app-service              │
│  Desired: 1 task                                        │
│  Running: 1 task                                        │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐                               │
│  │  Task-B (v1.1.0)     │  ✅ HEALTHY                   │
│  │  IP: 10.1.1.51       │                               │
│  │  Status: RUNNING     │  Serving 100% of traffic      │
│  └──────────────────────┘                               │
│                                                          │
│  Task-A: ❌ STOPPED (terminated)                        │
│                                                          │
└─────────────────────────────────────────────────────────┘

📊 Capacity: 100% (1 of 1 desired tasks)
🚦 Traffic: All requests → Task-B
✅ DEPLOYMENT COMPLETE!
```

---

## Key Takeaways

### 1. **Two Healthy Tasks Simultaneously**
From t=65s to t=66s, you have **BOTH** old and new tasks healthy and serving traffic. This guarantees zero downtime.

### 2. **ECS Controls Everything**
You don't manually:
- Start new tasks
- Route traffic
- Drain connections
- Stop old tasks

ECS orchestrates the entire process automatically based on health checks.

### 3. **Immutable Tasks**
Task-A is **NEVER updated**. Task-B is a completely new task with a new IP, new container, and new image. Task-A is simply terminated after Task-B is healthy.

### 4. **Capacity Temporarily Exceeds Desired Count**
With `deployment_maximum_percent = 200%`, you can run **up to 2x** your desired count during deployments. This is what enables zero-downtime.

### 5. **Traffic Routing**
If you're NOT using a load balancer (ALB/NLB), traffic routing depends on your app's discovery mechanism. With an ALB, the ALB automatically routes traffic only to healthy tasks.

---

## What If Health Checks Fail?

```
┌─────────────────────────────────────────────────────────┐
│  Task-B (v1.1.0) FAILS health checks                    │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────────┐  ┌──────────────────────┐    │
│  │  Task-A (v1.0.0)     │  │  Task-B (v1.1.0)     │    │
│  │  ✅ HEALTHY          │  │  ❌ UNHEALTHY        │    │
│  └──────────────────────┘  └──────────────────────┘    │
│         ↑                           ↑                   │
│         │                           │                   │
│    KEEPS serving           ECS stops this task         │
│    traffic                 (never gets traffic)         │
│                                                          │
│  ❌ Deployment FAILED                                   │
│  ✅ Task-A continues running (no downtime!)             │
│                                                          │
└─────────────────────────────────────────────────────────┘

Result: Old task stays healthy, deployment fails safely
Action: Fix the bug, deploy again with corrected image
```

---

## Summary

**Zero-downtime is achieved by:**

1. ✅ Starting new tasks BEFORE stopping old ones
2. ✅ Waiting for health checks to pass
3. ✅ Running old and new tasks simultaneously (briefly)
4. ✅ Draining old tasks gracefully
5. ✅ Stopping old tasks only after new ones are healthy

**You never have zero healthy tasks serving traffic at any point during the deployment.**

