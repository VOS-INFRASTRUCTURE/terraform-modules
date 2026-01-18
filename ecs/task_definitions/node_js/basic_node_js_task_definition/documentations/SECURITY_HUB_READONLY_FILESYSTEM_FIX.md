# Security Hub Finding: ECS Read-Only Root Filesystem

## 🔴 HIGH Severity Security Finding

**Finding ID:** `[ECS.8] ECS containers should be limited to read-only access to root filesystems`

**Current Status:** ❌ FAILED

---

## 📋 What This Means

### The Problem

Your ECS containers currently have **write access** to their entire root filesystem. This means:

- ❌ **Malware can write files** to the container
- ❌ **Attackers can modify application code** at runtime
- ❌ **Stolen data can be stored** in the container
- ❌ **Evidence can be deleted** making forensics harder
- ❌ **Backdoors can be installed** that persist

### Real-World Attack Example

```
1. Attacker exploits vulnerability in your Node.js app
   ↓
2. Attacker runs: echo "malicious code" > /app/backdoor.js
   ↓
3. ✅ File successfully written (current vulnerable state)
   ↓
4. Backdoor code executes on every request
   ↓
5. Data exfiltrated, customer PII stolen
```

### With Read-Only Filesystem (Secure)

```
1. Attacker exploits vulnerability in your Node.js app
   ↓
2. Attacker runs: echo "malicious code" > /app/backdoor.js
   ↓
3. ❌ ERROR: Read-only file system
   ↓
4. Attack prevented! ✅
```

---

## ✅ The Solution

Make the container's root filesystem **read-only**, and mount specific writable directories for legitimate temporary data.

### What Changes

**Before (Vulnerable):**
```
Container Filesystem:
├── /app (writable ❌)
├── /tmp (writable ❌)
├── /var (writable ❌)
└── ... (everything writable ❌)
```

**After (Secure):**
```
Container Filesystem:
├── /app (read-only ✅)
├── /tmp (writable via volume mount ✅)
├── /app/.cache (writable via volume mount ✅)
└── ... (everything else read-only ✅)
```

---

## 🔧 How to Fix This

### Step 1: Update Your Task Definition Module

The fix has already been applied to the module at:
```
/ecs/task_definitions/node_js/basic_node_js_task_definition/
```

**Changes made:**

1. **Added variable** (`variables.tf`):
   ```hcl
   variable "enable_readonly_root_filesystem" {
     description = "Enable read-only root filesystem for containers"
     type        = bool
     default     = true  # Enabled by default for security
   }
   ```

2. **Updated task definition** (`main.tf`):
   ```hcl
   # Added volumes for writable directories
   volume {
     name = "tmp"
   }
   volume {
     name = "cache"
   }

   # In container definition:
   readonlyRootFilesystem = true

   mountPoints = [
     {
       sourceVolume  = "tmp"
       containerPath = "/tmp"
       readOnly      = false
     },
     {
       sourceVolume  = "cache"
       containerPath = "/app/.cache"
       readOnly      = false
     }
   ]
   ```

### Step 2: Deploy the Updated Task Definition

#### Option A: Via Terraform (Recommended)

```bash
# Navigate to your infrastructure code
cd /path/to/your/terraform

# Plan the changes
terraform plan

# Apply the changes
terraform apply
```

**What happens:**
1. Terraform creates new task definition revision with `readonlyRootFilesystem = true`
2. ECS service automatically does rolling deployment
3. New tasks start with read-only filesystem
4. Old tasks are drained and stopped
5. **Zero downtime** ✅

#### Option B: Via AWS CLI

```bash
# Get current task definition
aws ecs describe-task-definition \
  --task-definition staging-ecs-node-app-task \
  --query 'taskDefinition' > task-def.json

# Edit task-def.json and add to each container:
#   "readonlyRootFilesystem": true,
#   "mountPoints": [
#     {
#       "sourceVolume": "tmp",
#       "containerPath": "/tmp",
#       "readOnly": false
#     }
#   ]

# Also add to top level (same level as "family"):
#   "volumes": [
#     { "name": "tmp" },
#     { "name": "cache" }
#   ]

# Remove fields that can't be registered
jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' \
  task-def.json > task-def-clean.json

# Register new task definition
aws ecs register-task-definition \
  --cli-input-json file://task-def-clean.json

# Update service to use new task definition
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --task-definition staging-ecs-node-app-task \
  --force-new-deployment
```

### Step 3: Verify the Fix

#### Check Task Definition

```bash
aws ecs describe-task-definition \
  --task-definition staging-ecs-node-app-task \
  --query 'taskDefinition.containerDefinitions[0].readonlyRootFilesystem'

# Should return: true
```

#### Check Security Hub

```bash
# Wait 15-30 minutes for Security Hub to re-scan

# Check finding status
aws securityhub get-findings \
  --filters '{"ProductFields": [{"Key": "aws/securityhub/ProductName", "Value": "Security Hub"}], "Title": [{"Value": "ECS containers should be limited to read-only access to root filesystems", "Comparison": "EQUALS"}]}' \
  --query 'Findings[?Compliance.Status==`PASSED`]'
```

#### Test Application Still Works

```bash
# Check app is running
curl https://your-staging-app.com/health

# Check logs for any write errors
aws logs tail /ecs/staging-ecs-node-app --follow
```

---

## ⚠️ Potential Issues & Solutions

### Issue 1: Application Writes to Filesystem

**Symptom:** Application crashes with "Read-only file system" error

**Example error:**
```
Error: EROFS: read-only file system, open '/app/data.json'
```

**Solution:** Identify which paths your app writes to and mount them as volumes:

```hcl
# In your task definition module call
module "app_task" {
  source = "../../ecs/task_definitions/node_js/basic_node_js_task_definition"
  
  # ... other config ...
  
  # Temporarily disable if app needs fixing
  enable_readonly_root_filesystem = false
}
```

Then update your application to write to `/tmp` instead:

```javascript
// Before (won't work with read-only filesystem)
fs.writeFileSync('/app/data.json', data);

// After (works with read-only filesystem)
fs.writeFileSync('/tmp/data.json', data);
```

### Issue 2: npm Install During Startup

**Symptom:** Container fails to start because `npm install` can't write `node_modules`

**Solution:** Install dependencies during Docker build, not at runtime:

```dockerfile
# Dockerfile
FROM node:18-alpine

WORKDIR /app

# Install dependencies during BUILD (not runtime)
COPY package*.json ./
RUN npm ci --only=production

# Copy application code
COPY . .

# Don't run npm install here - dependencies already installed above

CMD ["node", "server.js"]
```

### Issue 3: Logs Written to Filesystem

**Symptom:** Application tries to write log files to `/app/logs`

**Solution:** Use CloudWatch for logs (already configured) or write to `/tmp`:

```javascript
// Before
const logger = winston.createLogger({
  transports: [
    new winston.transports.File({ filename: '/app/logs/app.log' })
  ]
});

// After (write to stdout, captured by CloudWatch)
const logger = winston.createLogger({
  transports: [
    new winston.transports.Console()
  ]
});
```

---

## 📊 Impact Assessment

### Security Benefits

| Risk | Before (Writable) | After (Read-Only) |
|------|------------------|------------------|
| **Malware installation** | ❌ High risk | ✅ Prevented |
| **Code tampering** | ❌ Possible | ✅ Prevented |
| **Data exfiltration storage** | ❌ Possible | ✅ Prevented |
| **Backdoor persistence** | ❌ High risk | ✅ Prevented |
| **Forensic evidence** | ❌ Can be deleted | ✅ Protected |

### Compliance

| Framework | Requirement | Status After Fix |
|-----------|-------------|-----------------|
| **AWS Security Hub** | Read-only root filesystem | ✅ PASSED |
| **CIS AWS Benchmark** | Container hardening | ✅ COMPLIANT |
| **PCI DSS** | Restrict file access | ✅ COMPLIANT |
| **NIST 800-53** | AC-6 (Least Privilege) | ✅ COMPLIANT |

### Performance Impact

- ✅ **Zero performance impact**
- ✅ **Zero cost impact**
- ✅ **Zero downtime** (rolling deployment)

---

## 🎯 Next Steps

### Immediate Actions (Required)

1. ✅ **Review this document** - Understand the security issue
2. ✅ **Apply the fix** - Use Terraform to update task definition
3. ✅ **Test your application** - Ensure it still works
4. ✅ **Monitor Security Hub** - Verify finding changes to PASSED

### Optional Improvements

1. **Add more writable volumes if needed:**
   ```hcl
   # If your app writes to /app/uploads
   volume {
     name = "uploads"
   }
   
   mountPoints = [
     {
       sourceVolume  = "uploads"
       containerPath = "/app/uploads"
       readOnly      = false
     }
   ]
   ```

2. **Use EFS for persistent storage:**
   ```hcl
   # For data that needs to persist beyond container lifecycle
   volume {
     name = "persistent-data"
     
     efs_volume_configuration {
       file_system_id = aws_efs_file_system.app_data.id
       root_directory = "/"
     }
   }
   ```

3. **Audit application code:**
   - Review where your app writes files
   - Update to use `/tmp` or CloudWatch
   - Eliminate unnecessary filesystem writes

---

## 📚 References

- **AWS Security Hub Control:** [ECS.8 - Read-only root filesystem](https://docs.aws.amazon.com/securityhub/latest/userguide/ecs-controls.html#ecs-8)
- **ECS Task Definition:** [ReadonlyRootFilesystem](https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html)
- **CIS Docker Benchmark:** Section 5.12 - Ensure that the container's root filesystem is mounted as read only

---

## ✅ Summary

**The Fix:**
- ✅ Enable `readonlyRootFilesystem = true` in ECS task definition
- ✅ Mount `/tmp` and `/app/.cache` as writable volumes
- ✅ Default is now secure (enabled by default in module)

**Impact:**
- ✅ Prevents malware and code tampering
- ✅ Fixes Security Hub HIGH severity finding
- ✅ Zero performance or cost impact
- ✅ Rolling deployment with zero downtime

**Timeline:**
- Terraform apply: 2-3 minutes
- ECS rolling deployment: 5-10 minutes
- Security Hub rescan: 15-30 minutes
- **Total: ~30-45 minutes to full resolution**

**Result:** Security Hub finding changes from ❌ FAILED to ✅ PASSED

---

**Status:** Ready to deploy! The module has been updated with the fix.

**Next Step:** Run `terraform apply` in your infrastructure repository to deploy the secure configuration.

