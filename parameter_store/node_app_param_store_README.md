# Node.js App Parameter Store Configuration

## Overview

This file manages application configuration values using **AWS Systems Manager Parameter Store** (SSM). Parameters are injected as **environment variables** during container startup.

---

## Key Features

✅ **Terraform manages structure only** - Creates parameters with default values
✅ **AWS Console can update values** - Changes via UI won't be overwritten by Terraform
✅ **Zero-cost** - Using Standard tier (free for up to 10,000 parameters)
✅ **No restart required** - New ECS tasks automatically get updated values
✅ **Centralized configuration** - Manage all settings in one place

---

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Terraform creates SSM parameters with DEFAULT values      │
│    (only on initial creation)                                │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. You can update values via AWS Console/CLI                 │
│    (Terraform ignores these changes due to lifecycle rule)   │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. When ECS starts a new container:                          │
│    - Task Execution Role reads parameters from SSM           │
│    - Values are injected as environment variables            │
│    - Your app accesses them via process.env.PORT, etc.       │
└──────────────────────────────────────────────────────────────┘
```

---

## Parameters Created

### Configuration Parameters

| Parameter Name | Env Variable | Default Value | Description |
|----------------|--------------|---------------|-------------|
| `/${env}/node-app/config/port` | `PORT` | `3000` | Application server port |
| `/${env}/node-app/config/node_env` | `NODE_ENV` | `${env}` | Node.js environment (staging/production) |
| `/${env}/node-app/config/log_level` | `LOG_LEVEL` | `info` | Logging level (info/debug/warn/error) |
| `/${env}/node-app/config/request_timeout_ms` | `REQUEST_TIMEOUT_MS` | `30000` | HTTP request timeout (milliseconds) |
| `/${env}/node-app/config/max_upload_size_bytes` | `MAX_UPLOAD_SIZE_BYTES` | `10485760` | Max file upload size (10 MB) |

### Feature Flags

| Parameter Name | Env Variable | Default Value | Description |
|----------------|--------------|---------------|-------------|
| `/${env}/node-app/features/enable_debug` | `ENABLE_DEBUG` | `false` | Enable verbose debug logging |
| `/${env}/node-app/features/enable_cors` | `ENABLE_CORS` | `true` | Enable CORS for API requests |

**Example for staging environment:**
- Full path: `/staging/node-app/config/port`
- Injected as: `PORT=3000`

---

## Updating Parameter Values

### Via AWS Console

1. Go to **AWS Systems Manager** → **Parameter Store**
2. Search for `/staging/node-app/` (or your environment)
3. Click on a parameter (e.g., `/staging/node-app/config/port`)
4. Click **Edit**
5. Change the value (e.g., `3000` → `8080`)
6. Click **Save changes**

**Important:** Existing containers keep the old value. New containers (after restart/scale-up) get the new value.

### Via AWS CLI

```bash
# Update PORT to 8080
aws ssm put-parameter \
  --name "/staging/node-app/config/port" \
  --value "8080" \
  --overwrite

# Update LOG_LEVEL to debug
aws ssm put-parameter \
  --name "/staging/node-app/config/log_level" \
  --value "debug" \
  --overwrite

# View current value
aws ssm get-parameter \
  --name "/staging/node-app/config/port" \
  --query 'Parameter.Value' \
  --output text
```

---

## Applying Updates to Running Containers

After changing a parameter value, you need to restart the ECS tasks to pick up the new values:

### Option 1: Force New Deployment (Zero Downtime)

```bash
# Trigger rolling restart of ECS service
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

**What happens:**
- New tasks start with updated parameter values
- ALB routes traffic to new tasks once healthy
- Old tasks are drained and stopped
- Zero downtime (if minimum_healthy_percent configured correctly)

### Option 2: Manual Task Restart

```bash
# Stop a specific task (new one starts automatically)
aws ecs stop-task \
  --cluster staging-ecs-node-app-cluster \
  --task <task-id>
```

---

## Lifecycle Rule Explanation

```hcl
lifecycle {
  ignore_changes = [value]
}
```

**What this means:**
- **Initial creation**: Terraform sets the default value (e.g., PORT = 3000)
- **AWS Console updates**: You change value to 8080 via UI
- **Subsequent `terraform apply`**: Terraform sees the change but **ignores it** (won't revert to 3000)
- **Parameter deletion**: If you delete the parameter, Terraform will **recreate it** with the default value

**Why this is useful:**
- Allows DevOps to manage parameter values independently of infrastructure deployments
- No risk of Terraform overwriting production configuration values
- Infrastructure code defines the **structure**, operations manage the **values**

---

## Application Code Usage

Your Node.js application accesses these as standard environment variables:

```javascript
// server.js
const PORT = process.env.PORT || 3000;
const NODE_ENV = process.env.NODE_ENV || 'development';
const LOG_LEVEL = process.env.LOG_LEVEL || 'info';
const ENABLE_DEBUG = process.env.ENABLE_DEBUG === 'true';
const ENABLE_CORS = process.env.ENABLE_CORS === 'true';

const app = express();

// Use environment variables
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} in ${NODE_ENV} mode`);
  console.log(`Log level: ${LOG_LEVEL}`);
  console.log(`Debug enabled: ${ENABLE_DEBUG}`);
  console.log(`CORS enabled: ${ENABLE_CORS}`);
});

// CORS configuration
if (ENABLE_CORS) {
  app.use(cors({
    origin: process.env.CORS_ORIGIN || '*',
    credentials: true
  }));
}

// File upload size limit
app.use(express.json({ 
  limit: parseInt(process.env.MAX_UPLOAD_SIZE_BYTES) || 10485760 
}));

// Request timeout
app.use((req, res, next) => {
  req.setTimeout(parseInt(process.env.REQUEST_TIMEOUT_MS) || 30000);
  next();
});
```

---

## Cost Implications

**SSM Parameter Store (Standard Tier):**
- Storage: **FREE** (up to 10,000 parameters)
- API calls: **FREE** (standard throughput up to 1,000 TPS)
- Parameters created: **7** (well within free tier)

**Monthly Cost: $0.00** ✅

---

## Security Notes

### Parameter Type: `String` vs `SecureString`

Currently using `type = "String"` for **non-sensitive configuration values**.

**When to use each:**

| Type | Use For | Cost | Example |
|------|---------|------|---------|
| **String** | Non-sensitive config | FREE | PORT, LOG_LEVEL, feature flags |
| **SecureString** | Sensitive data | FREE + KMS costs | Passwords, API keys, tokens |

**For sensitive data (database passwords, API keys), use AWS Secrets Manager instead:**
- Better secret rotation support
- Automatic versioning
- More security features
- Cost: $0.40/secret/month

### IAM Permissions Required

**Task Execution Role** needs:
```json
{
  "Effect": "Allow",
  "Action": [
    "ssm:GetParameters"
  ],
  "Resource": [
    "arn:aws:ssm:eu-west-2:*:parameter/staging/node-app/*"
  ]
}
```

This is already configured in `node_app_iam_roles.tf` via `enable_secrets_access = true`.

---

## Troubleshooting

### Error: "Could not retrieve secret from parameter store"

**Cause:** Task Execution Role lacks SSM permissions.

**Solution:** Verify `enable_secrets_access = true` in `node_app_iam_roles.tf`.

### Container starts with old parameter value

**Cause:** Existing containers don't automatically reload parameters.

**Solution:** Force new deployment or restart tasks (see "Applying Updates" section above).

### Parameter not found

**Cause:** Parameter doesn't exist yet (maybe Terraform hasn't been applied).

**Solution:**
```bash
# Apply Terraform to create parameters
terraform apply

# Verify parameter exists
aws ssm get-parameter --name "/staging/node-app/config/port"
```

---

## Best Practices

### ✅ DO

- Use Parameter Store for **non-sensitive configuration** (port, timeouts, feature flags)
- Update values via AWS Console for **operational changes** (no code deploy needed)
- Use `lifecycle { ignore_changes = [value] }` to prevent Terraform overwriting manual updates
- Document parameter meanings in descriptions
- Use consistent naming conventions (e.g., `/${env}/${app}/category/param_name`)

### ❌ DON'T

- Store **sensitive data** (passwords, API keys) in Parameter Store String type - use Secrets Manager
- Remove `lifecycle { ignore_changes = [value] }` - this will cause Terraform to revert manual changes
- Change parameter **names** via AWS Console - this will cause Terraform drift (recreate instead)

---

## Adding New Parameters

1. **Add to `node_app_param_store.tf`:**

```hcl
resource "aws_ssm_parameter" "node_app_new_setting" {
  name        = "/${var.env}/node-app/config/new_setting"
  description = "Description of the new setting"
  type        = "String"
  value       = "default_value"
  
  lifecycle {
    ignore_changes = [value]
  }

  tags = {
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECS-Config"
    Application = "node-app"
  }
}
```

2. **Add to `node_app_task_definition.tf`:**

```hcl
secrets = [
  # ...existing parameters...
  {
    name      = "NEW_SETTING"
    valueFrom = aws_ssm_parameter.node_app_new_setting.arn
  }
]
```

3. **Apply Terraform:**

```bash
terraform apply
```

4. **Force ECS service update to inject new parameter:**

```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

---

## Related Files

- **`node_app_task_definition.tf`** - ECS task definition that injects these parameters
- **`node_app_iam_roles.tf`** - IAM roles with SSM permissions
- **`modules/ecs_task_execution_role/`** - Task Execution Role module

---

## References

- [AWS SSM Parameter Store Pricing](https://aws.amazon.com/systems-manager/pricing/)
- [SSM Parameter Store vs Secrets Manager](../modules/parameter_store/ParamStore.md)
- [ECS Task Definition Secrets](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/specifying-sensitive-data-parameters.html)

