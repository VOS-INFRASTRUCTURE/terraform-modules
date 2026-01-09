# Node.js App Secrets Manager Configuration

## Overview

This file manages **sensitive credentials** for the Node.js application using **AWS Secrets Manager**. Unlike Parameter Store (used for non-sensitive config), Secrets Manager provides:

- ✅ Automatic rotation support
- ✅ Advanced versioning (AWSCURRENT, AWSPENDING, AWSPREVIOUS)
- ✅ Audit logging (CloudTrail integration)
- ✅ Encryption at rest (always encrypted)
- ✅ Fine-grained access control

**Cost:** $0.40 per secret/month + $0.05 per 10,000 API calls

---

## Secrets Created

### 1. Combined Database Credentials (Recommended)

**Secret Name:** `staging/node-app/database/credentials`

**Format:** JSON object with both username and password

```json
{
  "username": "db_admin",
  "password": "super_secure_password_123!"
}
```

**Best for:** When username and password are always used together (database connections).

### 2. Separate Username and Password (Alternative)

**Secret Names:**
- `staging/node-app/database/username`
- `staging/node-app/database/password`

**Format:** Plain text strings

**Best for:** When you need granular access control (e.g., different services need only username, not password).

---

## Initial Setup Workflow

### Step 1: Deploy Infrastructure (Create Secret Structure)

```bash
cd environments/staging
terraform plan   # Review - will create 3 empty secrets
terraform apply  # Creates secrets WITHOUT values (secure!)
```

**What happens:**
- ✅ Creates 3 secrets in AWS Secrets Manager
- ✅ Secrets exist but have **NO values** yet
- ✅ No sensitive data in Terraform state
- ✅ No secrets in version control

### Step 2: Set Secret Values via AWS Console

#### Option A: Via AWS Console (Easiest)

1. Go to **AWS Console** → **Secrets Manager**
2. Find secret: `staging/node-app/database/credentials`
3. Click **Retrieve secret value** → **Edit**
4. Choose **Plaintext** and paste JSON:

```json
{
  "username": "your_actual_db_user",
  "password": "your_actual_db_password"
}
```

5. Click **Save**

#### Option B: Via AWS CLI

```bash
# Set combined credentials (JSON)
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/credentials \
  --secret-string '{
    "username": "your_actual_db_user",
    "password": "your_actual_db_password"
  }'

# Or set separate secrets (plain text)
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/username \
  --secret-string "your_actual_db_user"

aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/password \
  --secret-string "your_actual_db_password"
```

### Step 3: Verify Secret Values

```bash
# View combined credentials
aws secretsmanager get-secret-value \
  --secret-id staging/node-app/database/credentials \
  --query 'SecretString' \
  --output text | jq

# Output:
# {
#   "username": "your_actual_db_user",
#   "password": "your_actual_db_password"
# }
```

---

## Using Secrets in ECS Task Definition

### Approach 1: Inject as Environment Variables (Recommended)

**Update `node_app_task_definition.tf`:**

```hcl
resource "aws_ecs_task_definition" "node_app" {
  # ...existing code...
  
  container_definitions = jsonencode([{
    name  = "ecs-node-app"
    image = "..."
    
    # Inject secrets as environment variables at container startup
    secrets = [
      # From combined credentials secret
      {
        name      = "DB_USERNAME"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:password::"
      }
      
      # OR from separate secrets
      # {
      #   name      = "DB_USERNAME"
      #   valueFrom = aws_secretsmanager_secret.db_username.arn
      # },
      # {
      #   name      = "DB_PASSWORD"
      #   valueFrom = aws_secretsmanager_secret.db_password.arn
      # }
    ]
  }])
}
```

**Application code (Node.js):**

```javascript
// Secrets are available as environment variables
const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USERNAME,     // From Secrets Manager
  password: process.env.DB_PASSWORD,  // From Secrets Manager
  database: process.env.DB_NAME
};

const pool = mysql.createPool(dbConfig);
```

**Grant Task Execution Role permission:**

```hcl
# In node_app_iam_roles.tf.bak (already configured)
module "ecs_task_execution_role" {
  enable_secrets_access = true  # ✅ Grants secretsmanager:GetSecretValue
}
```

---

### Approach 2: Fetch at Runtime via SDK

**Update `node_app_iam_roles.tf`:**

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"
  
  project_id            = var.project_id
  env                   = var.env
  enable_secrets_access = true
  secrets_arns          = [
    aws_secretsmanager_secret.db_credentials.arn
  ]
}
```

**Application code (Node.js):**

```javascript
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({ region: 'eu-west-2' });

let cachedCredentials = null;
let cacheExpiry = 0;

async function getDbCredentials() {
  // Cache for 5 minutes to reduce API calls
  if (cachedCredentials && Date.now() < cacheExpiry) {
    return cachedCredentials;
  }
  
  const result = await client.send(
    new GetSecretValueCommand({ 
      SecretId: 'staging/node-app/database/credentials' 
    })
  );
  
  cachedCredentials = JSON.parse(result.SecretString);
  cacheExpiry = Date.now() + 5 * 60 * 1000;  // 5 minutes
  
  return cachedCredentials;
}

// Use in database connection
const mysql = require('mysql2/promise');

async function createDbPool() {
  const creds = await getDbCredentials();
  
  return mysql.createPool({
    host: process.env.DB_HOST,
    user: creds.username,      // From Secrets Manager
    password: creds.password,  // From Secrets Manager
    database: process.env.DB_NAME
  });
}

const pool = await createDbPool();
```

---

## Updating Secret Values

### Via AWS Console

1. Go to **Secrets Manager** → Find your secret
2. Click **Retrieve secret value** → **Edit**
3. Update the value
4. Click **Save**

**Important:** Existing containers keep old values. New containers (after restart/scale-up) get new values.

### Via AWS CLI

```bash
# Update combined credentials
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/credentials \
  --secret-string '{
    "username": "new_db_user",
    "password": "new_super_secure_password"
  }'

# Update separate password
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/password \
  --secret-string "new_super_secure_password"
```

### Apply to Running Containers

#### Option 1: If Using Environment Variable Injection

**Must restart ECS tasks** (secrets are injected only at container startup):

```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

#### Option 2: If Using Runtime SDK Fetch

**No restart needed!** App automatically gets new values on next fetch (after cache expires).

---

## Secret Rotation (Optional)

### Enable Automatic Rotation

Uncomment the rotation block in `node_app_secret_store.tf`:

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "${var.env}/node-app/database/credentials"
  
  # Enable automatic rotation every 30 days
  rotation_lambda_arn = aws_lambda_function.db_rotation.arn
  
  rotation_rules {
    automatically_after_days = 30
  }
}
```

**Requirements:**
1. Create a Lambda function that:
   - Generates new password
   - Updates database user password
   - Tests new credentials
   - Updates secret in Secrets Manager

2. Use runtime SDK fetch (not environment variable injection) for seamless rotation

**See:** `modules/secret_manager/SecretManager.md` for complete rotation setup guide.

---

## Cost Breakdown

### Monthly Cost Estimate

```
Secrets Storage:
  - db_credentials:  $0.40/month
  - db_username:     $0.40/month
  - db_password:     $0.40/month
  ─────────────────────────────
  Subtotal:          $1.20/month

API Calls (estimated):
  - 100,000 calls/month ÷ 10,000 × $0.05 = $0.50/month
  
TOTAL:               ~$1.70/month
```

**Cost Optimization:**

If you only use **one approach** (combined OR separate), cost drops to ~$0.90/month:

```
Option A: Combined credentials only
  - 1 secret × $0.40      = $0.40/month
  - API calls             = $0.50/month
  ─────────────────────────────────────
  TOTAL:                  = $0.90/month ✅

Option B: Separate username + password
  - 2 secrets × $0.40     = $0.80/month
  - API calls             = $0.50/month
  ─────────────────────────────────────
  TOTAL:                  = $1.30/month
```

**Recommendation:** Use **combined credentials** (Option A) unless you need granular access control.

---

## Security Best Practices

### ✅ DO

1. **Never store secret values in Terraform code** - Use AWS Console/CLI to set values
2. **Use runtime SDK fetch for rotation support** - Environment variables don't auto-update
3. **Enable CloudTrail logging** - Audit who accessed secrets
4. **Rotate credentials regularly** - 30-90 day intervals
5. **Use least privilege IAM** - Grant access only to specific secret ARNs
6. **Cache SDK fetches** - Reduce API calls and cost (5-minute cache recommended)

### ❌ DON'T

1. **Don't commit secret values to Git** - Ever!
2. **Don't use `secret_string` in Terraform** - Set values outside Terraform
3. **Don't grant `secretsmanager:*` on `"*"` resource** - Be specific
4. **Don't skip encryption** - Secrets Manager always encrypts (good!)
5. **Don't expose secrets in logs** - Mask/redact in application logs

---

## Troubleshooting

### Error: "ResourceNotFoundException: Secrets Manager can't find the specified secret"

**Cause:** Secret structure created but no value set yet.

**Solution:**
```bash
# Set initial value
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/credentials \
  --secret-string '{"username":"user","password":"pass"}'
```

### Error: "AccessDeniedException: User is not authorized to perform: secretsmanager:GetSecretValue"

**Cause:** Task Execution Role (for env vars) or Task Role (for SDK fetch) lacks permission.

**Solution:**
```hcl
# For environment variable injection
module "ecs_task_execution_role" {
  enable_secrets_access = true  # ✅
}

# For runtime SDK fetch
module "ecs_task_role" {
  enable_secrets_access = true
  secrets_arns = [aws_secretsmanager_secret.db_credentials.arn]
}
```

### Container starts with old secret value

**Cause:** Using environment variable injection - old containers keep old values.

**Solution:** Force new deployment:
```bash
aws ecs update-service \
  --cluster staging-ecs-node-app-cluster \
  --service staging-ecs-node-app-service \
  --force-new-deployment
```

---

## Migration from Parameter Store

If you previously stored DB credentials in Parameter Store:

### Step 1: Create secrets (already done via Terraform)

```bash
terraform apply
```

### Step 2: Copy values from Parameter Store to Secrets Manager

```bash
# Get old values
DB_USER=$(aws ssm get-parameter --name "/staging/node-app/db_username" --query 'Parameter.Value' --output text)
DB_PASS=$(aws ssm get-parameter --name "/staging/node-app/db_password" --query 'Parameter.Value' --output text --with-decryption)

# Set in Secrets Manager
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/credentials \
  --secret-string "{\"username\":\"$DB_USER\",\"password\":\"$DB_PASS\"}"
```

### Step 3: Update task definition to use Secrets Manager

```hcl
# Change from:
secrets = [
  {
    name      = "DB_USERNAME"
    valueFrom = aws_ssm_parameter.db_username.arn  # ❌ Old
  }
]

# To:
secrets = [
  {
    name      = "DB_USERNAME"
    valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:username::"  # ✅ New
  }
]
```

### Step 4: Delete old SSM parameters

```bash
terraform destroy -target=aws_ssm_parameter.db_username
terraform destroy -target=aws_ssm_parameter.db_password
```

---

## Related Files

- **`node_app_task_definition.tf`** - ECS task definition (inject secrets here)
- **`node_app_iam_roles.tf`** - IAM roles with Secrets Manager permissions
- **`node_app_param_store.tf`** - Non-sensitive configuration (PORT, LOG_LEVEL, etc.)
- **`modules/secret_manager/SecretManager.md`** - Complete Secrets Manager documentation

---

## Quick Reference

### View Secret Value

```bash
aws secretsmanager get-secret-value \
  --secret-id staging/node-app/database/credentials \
  --query 'SecretString' \
  --output text | jq
```

### Update Secret Value

```bash
aws secretsmanager put-secret-value \
  --secret-id staging/node-app/database/credentials \
  --secret-string '{"username":"newuser","password":"newpass"}'
```

### List All Secrets

```bash
aws secretsmanager list-secrets \
  --filters Key=name,Values=staging/node-app
```

### Delete Secret (with 30-day recovery window)

```bash
aws secretsmanager delete-secret \
  --secret-id staging/node-app/database/credentials \
  --recovery-window-in-days 30
```

### Restore Deleted Secret

```bash
aws secretsmanager restore-secret \
  --secret-id staging/node-app/database/credentials
```

---

## Next Steps

1. ✅ **Apply Terraform** - Creates secret structure
2. ✅ **Set secret values** - Via AWS Console/CLI (not Terraform)
3. ✅ **Update task definition** - Inject secrets as environment variables
4. ✅ **Grant IAM permissions** - Task Execution Role needs `secretsmanager:GetSecretValue`
5. ✅ **Test application** - Verify database connection works
6. 🔄 **Optional: Enable rotation** - For automated credential rotation

**Your secrets are now securely managed with AWS Secrets Manager!** 🔐

