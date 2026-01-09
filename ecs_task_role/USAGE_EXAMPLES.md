# ECS Task Role - Usage Examples

## Overview

This module creates an IAM role for your ECS application containers. The role grants permissions for your application code to access AWS services.

---

## Basic Usage (No Additional Permissions)

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id = "myapp"
  env        = "staging"
}
```

This creates a minimal role with only the trust policy (no permissions).

---

## Example 1: Enable ECS Exec (Debugging)

Allow interactive shell access to running containers via `aws ecs execute-command`:

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id      = "myapp"
  env             = "staging"
  enable_ecs_exec = true  # ✅ Enable SSH-like access for debugging
}
```

**What this enables:**
```bash
# Execute commands in running container
aws ecs execute-command \
  --cluster staging-ecs-cluster \
  --task <task-id> \
  --container myapp \
  --interactive \
  --command "/bin/bash"
```

---

## Example 2: Grant Secrets Manager Access

### Option A: Specific Secrets (Recommended)

Grant access to **specific secrets only** (principle of least privilege):

```hcl
# Create secrets first
resource "aws_secretsmanager_secret" "db_credentials" {
  name = "staging/myapp/db_credentials"
}

resource "aws_secretsmanager_secret" "api_keys" {
  name = "staging/myapp/api_keys"
}

# Grant access to those secrets
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id              = "myapp"
  env                     = "staging"
  enable_secrets_access   = true  # ✅ Enable secrets access
  secrets_arns            = [
    aws_secretsmanager_secret.db_credentials.arn,
    aws_secretsmanager_secret.api_keys.arn
  ]
}
```

### Option B: Wildcard Pattern (Environment-Scoped)

Grant access to **all secrets matching a pattern**:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id              = "myapp"
  env                     = "staging"
  enable_secrets_access   = true
  secrets_arns            = [
    "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:staging/myapp/*"
  ]
}
```

**This allows access to:**
- ✅ `staging/myapp/db_credentials`
- ✅ `staging/myapp/api_keys`
- ✅ `staging/myapp/jwt_secret`
- ❌ `production/myapp/db_credentials` (different environment)
- ❌ `staging/otherapp/secret` (different app)

### Option C: All Secrets (NOT Recommended for Production)

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id              = "myapp"
  env                     = "staging"
  enable_secrets_access   = true
  secrets_arns            = ["*"]  # ⚠️ Grants access to ALL secrets
}
```

**Only use this for:**
- Development environments
- Proof-of-concept testing
- When you're certain the app needs access to many secrets

---

## Example 3: Grant SSM Parameter Store Access

### Option A: Specific Parameters (Recommended)

Grant access to **specific parameters only**:

```hcl
# Create parameters first
resource "aws_ssm_parameter" "app_config" {
  name  = "/staging/myapp/config"
  type  = "String"
  value = "some-config-value"
}

resource "aws_ssm_parameter" "feature_flags" {
  name  = "/staging/myapp/features"
  type  = "String"
  value = "feature1:enabled,feature2:disabled"
}

# Grant access to those parameters
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id                     = "myapp"
  env                            = "staging"
  enable_parameter_store_access  = true  # ✅ Enable parameter store access
  parameter_arns                 = [
    aws_ssm_parameter.app_config.arn,
    aws_ssm_parameter.feature_flags.arn
  ]
}
```

### Option B: Wildcard Pattern (Environment-Scoped)

Grant access to **all parameters matching a pattern**:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id                     = "myapp"
  env                            = "staging"
  enable_parameter_store_access  = true
  parameter_arns                 = [
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/staging/myapp/*"
  ]
}
```

**This allows access to:**
- ✅ `/staging/myapp/config`
- ✅ `/staging/myapp/features`
- ✅ `/staging/myapp/database/host`
- ❌ `/production/myapp/config` (different environment)
- ❌ `/staging/otherapp/config` (different app)

**Application code example (Node.js):**

```javascript
const { SSMClient, GetParameterCommand } = require('@aws-sdk/client-ssm');

const client = new SSMClient({ region: 'eu-west-2' });

async function getAppConfig() {
  const result = await client.send(
    new GetParameterCommand({ Name: '/staging/myapp/config' })
  );
  
  return result.Parameter.Value;
}

// Use it
const config = await getAppConfig();  // Automatically uses task role!
```

---

## Example 4: Grant S3 Access

### Option A: Specific Buckets

```hcl
resource "aws_s3_bucket" "uploads" {
  bucket = "staging-myapp-uploads"
}

resource "aws_s3_bucket" "backups" {
  bucket = "staging-myapp-backups"
}

module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id       = "myapp"
  env              = "staging"
  enable_s3_access = true
  s3_bucket_arns   = [
    "${aws_s3_bucket.uploads.arn}",
    "${aws_s3_bucket.uploads.arn}/*",      # Objects in bucket
    "${aws_s3_bucket.backups.arn}",
    "${aws_s3_bucket.backups.arn}/*"
  ]
}
```

**Important:** You need **both** the bucket ARN and `bucket/*` pattern:
- `arn:aws:s3:::bucket-name` - For `ListBucket` operations
- `arn:aws:s3:::bucket-name/*` - For `GetObject`, `PutObject`, `DeleteObject`

### Option B: Wildcard Pattern

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id       = "myapp"
  env              = "staging"
  enable_s3_access = true
  s3_bucket_arns   = [
    "arn:aws:s3:::staging-myapp-*",
    "arn:aws:s3:::staging-myapp-*/*"
  ]
}
```

---

## Example 4: Combined Permissions

Real-world setup with multiple permissions:

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id      = "myapp"
  env             = "staging"
  
  # Debugging
  enable_ecs_exec = true
  
  # S3 access for file uploads
  enable_s3_access = true
  s3_bucket_arns   = [
    aws_s3_bucket.uploads.arn,
    "${aws_s3_bucket.uploads.arn}/*"
  ]
  
  # Secrets access for DB credentials and API keys
  enable_secrets_access = true
  secrets_arns          = [
    aws_secretsmanager_secret.db_credentials.arn,
    aws_secretsmanager_secret.stripe_api_key.arn,
    aws_secretsmanager_secret.sendgrid_api_key.arn
  ]
}
```

---

## Example 5: Combined Permissions

Real-world setup with multiple permissions:

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id      = "myapp"
  env             = "staging"
  
  # Debugging
  enable_ecs_exec = true
  
  # S3 access for file uploads
  enable_s3_access = true
  s3_bucket_arns   = [
    aws_s3_bucket.uploads.arn,
    "${aws_s3_bucket.uploads.arn}/*"
  ]
  
  # Secrets access for DB credentials and API keys
  enable_secrets_access = true
  secrets_arns          = [
    aws_secretsmanager_secret.db_credentials.arn,
    aws_secretsmanager_secret.stripe_api_key.arn,
    aws_secretsmanager_secret.sendgrid_api_key.arn
  ]
  
  # Parameter Store access for runtime config
  enable_parameter_store_access = true
  parameter_arns                = [
    "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/staging/myapp/*"
  ]
}
```

---

## Example 6: Custom Role Name

Override the default role name:

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"

  project_id = "myapp"
  env        = "staging"
  role_name  = "my-custom-ecs-task-role"  # Instead of "staging-ecs-task-role"
}
```

---

## How to Use in Task Definition

```hcl
resource "aws_ecs_task_definition" "app" {
  family = "staging-myapp-task"
  
  # Task Execution Role (ECS uses this to pull images, write logs)
  execution_role_arn = module.ecs_task_execution_role.role.arn
  
  # Task Role (Your app uses this to access AWS services)
  task_role_arn = module.ecs_task_role.role.arn  # ✅ Reference the role here
  
  container_definitions = jsonencode([{
    name  = "myapp"
    image = "123456789.dkr.ecr.eu-west-2.amazonaws.com/myapp:latest"
    # ... rest of config
  }])
}
```

---

## Application Code Examples

### Fetching Secrets in Node.js

```javascript
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({ region: 'eu-west-2' });

async function getDbCredentials() {
  const result = await client.send(
    new GetSecretValueCommand({ SecretId: 'staging/myapp/db_credentials' })
  );
  
  return JSON.parse(result.SecretString);
}

// Use it
const creds = await getDbCredentials();
console.log(creds.db_username);  // Automatically uses task role!
```

### Uploading to S3 in Node.js

```javascript
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({ region: 'eu-west-2' });

async function uploadFile(fileBuffer, fileName) {
  await s3.send(new PutObjectCommand({
    Bucket: 'staging-myapp-uploads',
    Key: fileName,
    Body: fileBuffer
  }));
}

// Use it
await uploadFile(Buffer.from('Hello World'), 'test.txt');  // Automatically uses task role!
```

---

## Outputs

The module provides a single object output with all role details:

```hcl
module "ecs_task_role" {
  source = "./modules/ecs_task_role"
  # ... config
}

# Access outputs
output "task_role_details" {
  value = {
    arn  = module.ecs_task_role.role.arn   # "arn:aws:iam::123:role/staging-ecs-task-role"
    name = module.ecs_task_role.role.name  # "staging-ecs-task-role"
    id   = module.ecs_task_role.role.id    # "staging-ecs-task-role"
  }
}
```

---

## Security Best Practices

### ✅ DO

1. **Use specific secret ARNs** instead of wildcards when possible
2. **Scope S3 access** to specific buckets only
3. **Enable only needed permissions** (don't enable everything)
4. **Use environment-scoped patterns** (e.g., `staging/*` not `*`)
5. **Different roles per environment** (staging vs production)

### ❌ DON'T

1. **Don't use `"*"` for Resource** unless absolutely necessary
2. **Don't grant admin permissions** (`secretsmanager:*`, `s3:*` on all resources)
3. **Don't share task roles** across unrelated applications
4. **Don't hardcode secret names** in the module (pass as variables)

---

## Troubleshooting

### Error: "Access Denied" when fetching secrets

**Cause:** Either:
- `enable_secrets_access = false` (not enabled)
- Secret ARN not in `secrets_arns` list
- Wrong secret ARN format

**Solution:**
```hcl
enable_secrets_access = true
secrets_arns = [
  "arn:aws:secretsmanager:eu-west-2:123456:secret:staging/myapp/db-ABC123"  # Full ARN
]
```

### Error: "Access Denied" when accessing S3

**Cause:** Missing bucket ARN or object ARN pattern

**Solution:** Include both:
```hcl
s3_bucket_arns = [
  "arn:aws:s3:::my-bucket",      # For ListBucket
  "arn:aws:s3:::my-bucket/*"     # For Get/Put/Delete
]
```

### How to find secret ARN?

```bash
# List all secrets
aws secretsmanager list-secrets

# Get specific secret ARN
aws secretsmanager describe-secret \
  --secret-id staging/myapp/db_credentials \
  --query 'ARN' \
  --output text
```

### How to test permissions?

From inside your running container:

```bash
# Verify task role credentials are available
curl http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI

# Test secret access (requires AWS CLI in container)
aws secretsmanager get-secret-value --secret-id staging/myapp/db_credentials

# Test S3 access
aws s3 ls s3://staging-myapp-uploads/
```

---

## Related Documentation

- [TaskRole.md](./TaskRole.md) - Complete module documentation
- [ECS Task IAM Roles (AWS Docs)](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- [Task Execution Role Module](../ecs_task_execution_role/)

