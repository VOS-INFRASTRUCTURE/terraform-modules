# ECS Deployment Failure Safety - Detailed Explanation

## 🛡️ TL;DR - Your Service is Safe

**If a deployment fails halfway through:**
- ✅ **OLD tasks keep running** (no interruption)
- ✅ **Service continues serving traffic** (zero downtime)
- ✅ **NEW unhealthy tasks are stopped** (automatic cleanup)
- ❌ **Deployment marked as FAILED** (no partial rollout)

**Result:** Your users experience ZERO downtime, and your service continues running the previous working version.

---

## 🔬 Detailed Failure Scenarios

### Scenario 1: Health Check Failure (Most Common)

**What happens:**

```
t=0s:    [Task-A:v1.0.0] ✅ HEALTHY                     ← Old version running
         Status: Serving 100% of traffic
         
         🚀 Deploy v1.1.0 triggered (with a bug!)
         
t=5s:    [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] ⏳ STARTING
         Status: Old task serves traffic, new task provisioning
         
t=15s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] 🏥 RUNNING (health checks starting)
         Status: Old task serves traffic, new task being checked
         
t=60s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] 🏥 RUNNING (startPeriod ends)
         Health Check: GET http://10.1.1.51:3000/health
         Response: HTTP 500 (BUG IN CODE!)
         
t=90s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] ❌ UNHEALTHY (3 failures)
         ECS Action: Mark Task-B as UNHEALTHY
         
t=91s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] 🛑 STOPPING
         ECS Action: Stop unhealthy task
         
t=96s:   [Task-A:v1.0.0] ✅ HEALTHY  
         Status: Only old task running
         Deployment: FAILED
         Traffic: 100% served by Task-A (old version)
```

**Key Points:**
- ❌ Task-B **NEVER** receives production traffic (failed health checks)
- ✅ Task-A **NEVER** stops (ECS keeps it running when deployment fails)
- ✅ Users **NEVER** experience downtime

---

### Scenario 2: Application Crash on Startup

**What happens:**

```
t=0s:    [Task-A:v1.0.0] ✅ HEALTHY
         
t=5s:    [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] ⏳ STARTING
         
t=10s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] 💥 CRASHED
         Container Exit Code: 1 (app crashed due to missing ENV var)
         
t=11s:   [Task-A:v1.0.0] ✅ HEALTHY  
         ECS Action: Stopped Task-B (essential container exited)
         Deployment: FAILED
         
Result: Task-A continues serving traffic, no downtime
```

---

### Scenario 3: Insufficient Memory/CPU

**What happens:**

```
t=0s:    [Task-A:v1.0.0] ✅ HEALTHY
         
t=5s:    [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] ⏳ PROVISIONING
         
t=30s:   [Task-A:v1.0.0] ✅ HEALTHY  [Task-B:v1.1.0] 💾 OUT OF MEMORY
         Task-B: Memory usage 600MB (limit: 512MB)
         Container killed by ECS
         
t=31s:   [Task-A:v1.0.0] ✅ HEALTHY
         ECS Action: Stopped Task-B (OOMKilled)
         Deployment: FAILED
         
Result: Task-A continues serving traffic, no downtime
```

---

## 🔐 ECS Safety Guarantees

### How ECS Protects Your Service

ECS uses a **deployment circuit breaker** mechanism:

1. **Monitors deployment health**
   - Tracks task launch failures
   - Tracks health check failures
   - Tracks container crashes

2. **Detects failure patterns**
   - If new tasks consistently fail → deployment is failing
   - Circuit breaker triggers after multiple failures

3. **Prevents bad rollout**
   - Stops starting new tasks
   - Keeps old tasks running
   - Marks deployment as FAILED

4. **Maintains service availability**
   - Old tasks continue serving traffic
   - No traffic sent to unhealthy tasks
   - Service never drops below `deployment_minimum_healthy_percent`

---

## 📊 Deployment Configuration Impact

### Current Configuration (Your Setup)

```hcl
deployment_minimum_healthy_percent = 50   # Min 50% capacity
deployment_maximum_percent         = 200  # Max 200% capacity
desired_count                      = 1    # Want 1 task
```

**With `desired_count = 1`:**

| Phase | Healthy Tasks | Capacity | User Impact |
|-------|---------------|----------|-------------|
| Normal operation | 1 old | 100% | ✅ Normal |
| Deployment starts | 1 old + 1 new starting | 100%→150% | ✅ Normal (old serves) |
| **NEW TASK FAILS** | 1 old | 100% | ✅ Normal (old continues) |
| Deployment fails | 1 old | 100% | ✅ Normal (no change) |

**Result:** Users NEVER experience degraded service or downtime.

---

### With `desired_count = 2`

| Phase | Healthy Tasks | Capacity | User Impact |
|-------|---------------|----------|-------------|
| Normal operation | 2 old | 100% | ✅ Normal |
| Deployment starts | 2 old + 1 new starting | 150% | ✅ Normal (olds serve) |
| **NEW TASK FAILS** | 2 old | 100% | ✅ Normal (olds continue) |
| Deployment fails | 2 old | 100% | ✅ Normal (no change) |

---

## 🎯 The GitHub Actions Workflow Safety

### What `wait-for-service-stability: true` Does

```yaml
- name: Deploy Amazon ECS task definition
  uses: aws-actions/amazon-ecs-deploy-task-definition@v2
  with:
    wait-for-service-stability: true  # ← Critical safety feature
```

**This step will:**

1. **Register new task definition** (revision N+1)
2. **Update ECS service** to use new revision
3. **Wait for deployment to complete** (polls ECS every 15 seconds)
4. **Monitor deployment status:**
   - ✅ If deployment succeeds → step succeeds, workflow continues
   - ❌ If deployment fails → **step fails, workflow fails**

**When deployment fails:**
- GitHub Actions workflow shows ❌ FAILED
- GitHub Actions email notification sent
- ECS service still running with old tasks
- No downtime occurred

---

## 🔍 How to Verify Safety After Failure

### Check Running Tasks (Verify Old Version Still Running)

```bash
aws ecs list-tasks \
  --cluster ecs-node-app-cluster \
  --service-name staging-ecs-node-app-service

# If deployment failed, you'll see:
# - Only old tasks running
# - No new (unhealthy) tasks
```

### Check Service Events (See Failure Reason)

```bash
aws ecs describe-services \
  --cluster ecs-node-app-cluster \
  --services staging-ecs-node-app-service \
  --query 'services[0].events[:10]'

# You'll see events like:
# - "service staging-ecs-node-app-service has started 1 tasks: task abc123."
# - "service staging-ecs-node-app-service has stopped 1 running tasks: task abc123."
# - "service staging-ecs-node-app-service was unable to place a task."
```

### Check CloudWatch Logs (See Why Task Failed)

```bash
aws logs tail /ecs/staging-ecs-node-app --follow

# Look for:
# - Application crash logs
# - Health check endpoint errors
# - Missing environment variable errors
```

---

## 💡 Common Failure Reasons & Fixes

### 1. Health Check Endpoint Returns Non-200

**Error:**
```
Health check failed: HTTP GET http://10.1.1.51:3000/health returned 500
```

**Fix:**
```javascript
// Ensure health endpoint returns 200
app.get('/health', (req, res) => {
  // Check database connection, dependencies, etc.
  res.status(200).json({ status: 'healthy' });
});
```

---

### 2. Application Crashes on Startup

**Error:**
```
Container exited with code 1
Error: Cannot find module 'express'
```

**Fix:**
```dockerfile
# Ensure dependencies are installed in Dockerfile
RUN npm ci --production
```

---

### 3. Missing Environment Variables

**Error:**
```
TypeError: Cannot read property 'DB_HOST' of undefined
```

**Fix:**
```hcl
# Add to task definition
environment = [
  { name = "DB_HOST", value = "postgres.example.com" },
  { name = "NODE_ENV", value = "production" }
]
```

---

### 4. Port Mismatch

**Error:**
```
Health check failed: Connection refused on port 3000
```

**Fix:**
```javascript
// Ensure app listens on correct port
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

---

### 5. Out of Memory

**Error:**
```
Task stopped: OutOfMemoryError: Container killed due to memory usage
```

**Fix:**
```hcl
# Increase task memory in task definition
resource "aws_ecs_task_definition" "node_app" {
  memory = "1024"  # Increased from 512
}
```

---

## 🚀 Recovery Workflow

### When Deployment Fails:

```
1. GitHub Actions workflow fails ❌
   ↓
2. Check GitHub Actions logs for error
   ↓
3. Check CloudWatch Logs for application error
   ↓
4. Fix the issue in your code
   ↓
5. Commit and push to trigger new deployment
   ↓
6. New deployment succeeds ✅
   ↓
7. Old tasks drained and replaced
```

**During this entire time:** Old version continues serving traffic!

---

## 🎯 Answer to Your Question

### **Q: "If deployment fails halfway, the service running before will not be affected?"**

✅ **CORRECT - The running service is NOT affected!**

**What happens:**
1. New tasks start
2. New tasks fail health checks
3. **ECS keeps old tasks running** (critical safety feature)
4. ECS stops new unhealthy tasks
5. Deployment marked as FAILED
6. **Old tasks continue serving 100% of traffic**

**Visual Summary:**

```
Before deployment:
[Old v1.0.0] ✅ ← Serving traffic

During failed deployment:
[Old v1.0.0] ✅ ← Still serving traffic
[New v1.1.0] ❌ ← Failed, being stopped

After failed deployment:
[Old v1.0.0] ✅ ← STILL serving traffic (no change!)

Deployment status: FAILED
User impact: ZERO (no downtime)
```

---

## 📚 ECS Deployment Safety Features

| Feature | Purpose | Protects Against |
|---------|---------|------------------|
| **Health checks** | Verify tasks are healthy before routing traffic | Bad deployments reaching users |
| **Minimum healthy percent** | Guarantee minimum capacity during deploy | Service outages |
| **Maximum percent** | Control resource usage during deploy | Over-provisioning |
| **Deployment circuit breaker** | Automatically stop failing deployments | Continuous failed task launches |
| **Rolling updates** | Gradual replacement of tasks | Big-bang failures |
| **startPeriod grace** | Give app time to initialize | Premature health check failures |

---

## ✅ Summary

**Your service is ALWAYS safe during failed deployments:**

1. ✅ Old tasks keep running (no interruption)
2. ✅ Traffic continues flowing to old tasks (zero downtime)
3. ✅ New unhealthy tasks are stopped automatically (cleanup)
4. ❌ Deployment marked as FAILED (clear signal to developer)
5. 🔄 Fix and redeploy when ready (old version holds the fort)

**This is the power of ECS rolling deployments with health checks!** 🛡️

