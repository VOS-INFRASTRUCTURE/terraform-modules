# Secrets Management in ECS (AWS Secrets Manager)

This document explains **how secrets are accessed by ECS task containers**, the **two supported patterns**, their **security model**, and **best practices** for Node.js applications running on **ECS (Fargate or EC2)**.

---

## 🎯 Goals

* Securely access secrets from ECS tasks
* Avoid hard-coded credentials
* Support secret rotation
* Minimize operational risk and API calls
* Clearly separate IAM responsibilities

---

## 🧠 Core Concepts

### What is a "Secret" in AWS Secrets Manager?

* A **secret** is a single object
* The value is usually a **JSON document**
* One `GetSecretValue` call returns the **entire value**

Example secret value:

```json
{
  "username": "db_user",
  "password": "super-secret",
  "host": "db.example.com",
  "port": 5432
}
```

---

## 📊 Secret Parameter Types & Data Formats

AWS Secrets Manager supports **two primary data types** for storing secret values:

| Type | Description | Use Case | Size Limit |
|------|-------------|----------|------------|
| **SecretString** | UTF-8 encoded text (JSON, plain text, etc.) | Most common use case | 65,536 bytes |
| **SecretBinary** | Base64-encoded binary data | Certificates, encryption keys | 65,536 bytes |

### 1. SecretString (Most Common)

SecretString is a **text-based format** that can store:

#### A. JSON Object (Recommended)

Best practice for storing **multiple related values** (credentials, config):

```json
{
  "username": "admin",
  "password": "P@ssw0rd!",
  "host": "db.example.com",
  "port": 5432,
  "database": "production_db",
  "ssl": true
}
```

**Supported JSON data types:**
- `string`: `"value"`
- `number`: `123`, `45.67`
- `boolean`: `true`, `false`
- `null`: `null`
- `array`: `["item1", "item2"]`
- `object`: `{"key": "value"}`

#### B. Plain Text String

For **single-value secrets** (API keys, tokens):

```text
sk-1234567890abcdef1234567890abcdef
```

#### C. Key-Value Pairs (Alternative JSON Format)

```json
{
  "API_KEY": "abc123",
  "API_SECRET": "xyz789",
  "WEBHOOK_URL": "https://api.example.com/webhook"
}
```

#### D. Nested JSON Structures

For **complex configurations**:

```json
{
  "database": {
    "primary": {
      "host": "db-primary.example.com",
      "port": 5432,
      "credentials": {
        "username": "admin",
        "password": "secret123"
      }
    },
    "replica": {
      "host": "db-replica.example.com",
      "port": 5432
    }
  },
  "redis": {
    "host": "redis.example.com",
    "port": 6379,
    "password": "redis_password"
  },
  "feature_flags": {
    "enable_new_ui": true,
    "max_upload_size_mb": 100,
    "allowed_domains": ["example.com", "app.example.com"]
  }
}
```

---

### 2. SecretBinary

Binary format for **non-text data** (stored as Base64):

**Use cases:**
- SSL/TLS certificates
- Private keys (RSA, EC)
- Encryption keys
- Binary tokens

**Example (Terraform):**

```hcl
resource "aws_secretsmanager_secret_version" "ssl_cert" {
  secret_id     = aws_secretsmanager_secret.ssl.id
  secret_binary = filebase64("${path.module}/certificate.pem")
}
```

**Example (AWS CLI):**

```bash
aws secretsmanager put-secret-value \
  --secret-id prod/ssl-certificate \
  --secret-binary fileb://certificate.pem
```

**Retrieving binary secrets (Node.js):**

```typescript
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({});

async function getBinaryCert() {
  const result = await client.send(
    new GetSecretValueCommand({ SecretId: "prod/ssl-certificate" })
  );
  
  // SecretBinary is returned as a Uint8Array
  const certData = result.SecretBinary;
  
  // Convert to string if needed
  const certString = Buffer.from(certData).toString('utf-8');
  return certString;
}
```

---

## 🔢 Supported Data Type Details

### In JSON SecretString

| JSON Type | Example | Notes |
|-----------|---------|-------|
| **String** | `"Hello World"` | UTF-8 text, can contain special chars |
| **Number** | `42`, `3.14159`, `-100` | Integer or floating-point |
| **Boolean** | `true`, `false` | Lowercase only (JSON spec) |
| **Null** | `null` | Represents absence of value |
| **Array** | `[1, 2, 3]` | Ordered list of any JSON types |
| **Object** | `{"key": "value"}` | Nested key-value pairs |

### Special Characters & Escaping

JSON strings support escape sequences:

```json
{
  "password": "P@ss\"w0rd\\with\\backslashes",
  "newline": "Line1\nLine2",
  "unicode": "emoji: \u2764\uFE0F"
}
```

| Escape | Meaning |
|--------|---------|
| `\"` | Double quote |
| `\\` | Backslash |
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\uXXXX` | Unicode character |

---

## 📦 Parsing Secrets in Application Code

### Node.js / TypeScript

```typescript
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({});

async function getSecrets() {
  const result = await client.send(
    new GetSecretValueCommand({ SecretId: "prod/app-config" })
  );

  // Parse JSON string
  const secrets = JSON.parse(result.SecretString!);
  
  // Access values with type safety
  const dbConfig = {
    host: secrets.database.host,          // string
    port: secrets.database.port,          // number
    ssl: secrets.database.ssl,            // boolean
    allowedDomains: secrets.allowed_domains // array
  };
  
  return dbConfig;
}
```

### Python (boto3)

```python
import json
import boto3

client = boto3.client('secretsmanager')

def get_secrets():
    response = client.get_secret_value(SecretId='prod/app-config')
    
    # Parse JSON string
    secrets = json.loads(response['SecretString'])
    
    # Access values
    db_host = secrets['database']['host']      # str
    db_port = secrets['database']['port']      # int
    ssl_enabled = secrets['database']['ssl']   # bool
    
    return secrets
```

---

## ⚠️ Important Limits & Constraints

| Limit | Value | Notes |
|-------|-------|-------|
| **Max secret size** | 65,536 bytes (64 KB) | Applies to both SecretString and SecretBinary |
| **Secret name length** | 1-512 characters | Must be unique within account/region |
| **Allowed characters** | `a-z A-Z 0-9 /_+=.@-` | Alphanumeric and special chars only |
| **API rate limits** | 5,000 requests/sec | Shared across account (use caching!) |
| **Version stages** | 20 per secret | AWSCURRENT, AWSPENDING, custom stages |

### Size Calculation

```bash
# Check secret size before uploading
echo '{"username":"admin","password":"secret"}' | wc -c
# Output: 41 bytes (well under 64 KB limit)
```

If you need to store **larger data** (>64 KB):
- Store in **S3** and put the S3 path in Secrets Manager
- Use **AWS Systems Manager Parameter Store** (supports up to 8 KB for standard, 4-8 KB for advanced)
- Split into multiple secrets

---

## 🎨 Secret Naming Conventions

Best practices for organizing secrets:

```
Environment/Service/Component/Type

Examples:
  prod/database/primary/credentials
  prod/api/stripe/api-key
  staging/redis/connection-string
  prod/ssl/certificate
  dev/app/config
```

**Benefits:**
- Easy to organize IAM policies by prefix
- Clear environment separation
- Searchable and filterable

**Terraform example with naming convention:**

```hcl
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.env}/database/primary/credentials"
  description = "Primary database credentials for ${var.env}"
  
  tags = {
    Environment = var.env
    Service     = "database"
    ManagedBy   = "Terraform"
  }
}
```

---

## 🔄 AWS Secrets Manager: Built-In Automatic Rotation Explained

### What Does "Built-In Rotation" Mean?

**Built-in rotation** means AWS Secrets Manager can **automatically change secret values on a schedule** without manual intervention. This is a **service-level feature**, not a property you set on individual keys within a secret.

**Important:** You don't set rotation on individual fields like `{app_key: AUTO_ROTATE}`. Instead, you configure rotation for the **entire secret object**.

---

### How Automatic Rotation Works

```
┌──────────────────────────────────────────────────────────────┐
│ 1. Schedule Trigger (e.g., every 30 days)                    │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 2. Secrets Manager invokes a Lambda function                 │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 3. Lambda generates new credentials                          │
│    - Creates new password in target system (RDS, etc.)       │
│    - Tests new credentials work                              │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 4. Secrets Manager stores new version with AWSPENDING stage  │
└──────────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────────┐
│ 5. After verification, new version becomes AWSCURRENT        │
│    - Old version is retained (can be accessed if needed)     │
└──────────────────────────────────────────────────────────────┘
```

---

### Supported Services with Managed Rotation

AWS provides **pre-built Lambda rotation functions** for these services:

| Service | Rotation Type | What Gets Rotated |
|---------|---------------|-------------------|
| **Amazon RDS** (MySQL, PostgreSQL, Oracle, SQL Server) | Single user or alternating users | Database password |
| **Amazon Aurora** (MySQL, PostgreSQL) | Single user or alternating users | Database password |
| **Amazon Redshift** | Single user | Database password |
| **Amazon DocumentDB** | Single user or alternating users | Database password |
| **Amazon ElastiCache** (Redis) | Single user | AUTH token |

**These rotations are "built-in"** because AWS provides:
- ✅ Pre-written Lambda functions (no custom code needed)
- ✅ Automated setup via Secrets Manager console/API
- ✅ Tested rotation logic for each service

---

### Custom Rotation (For Other Services)

For services **not in the list above**, you need to write your own Lambda function:

| Service Example | What You Need to Do |
|----------------|---------------------|
| **API Keys** (Stripe, Twilio, etc.) | Write Lambda to call the provider's API to rotate keys |
| **SSH Keys** | Write Lambda to generate new keypairs and update systems |
| **JWT Signing Secrets** | Write Lambda to generate new secrets and coordinate app deployments |
| **OAuth Client Secrets** | Write Lambda to call OAuth provider's API |

**This is NOT "built-in"** because you must provide the rotation logic.

---

### Rotation Strategies

#### 1. Single User Rotation

```
Old credentials → immediately replaced → new credentials

Timeline:
  Day 0:  password = "old_password_123"
  Day 30: password = "new_password_456"  ← old password stops working
```

**Risk:** Brief downtime if rotation fails or apps can't reconnect fast enough.

**Use when:** You control all applications and can handle brief credential changes.

#### 2. Alternating Users Rotation (Recommended for Databases)

```
User A active → create User B → switch to User B → User A becomes standby

Timeline:
  Day 0:   Active: user_a (password_1)
  Day 30:  Create: user_b (password_2), switch apps to user_b
  Day 60:  Update: user_a (password_3), switch apps to user_a
  Day 90:  Update: user_b (password_4), switch apps to user_b
```

**Benefits:**
- ✅ Zero downtime (old credentials remain valid during rotation)
- ✅ Apps can reconnect at their own pace
- ✅ Rollback option if new credentials fail

**Use when:** High availability required (production databases).

---

### Terraform Example: Enable Rotation for RDS

```hcl
# ─────────────────────────────────────────────────────────────
# 1. Create the secret
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "${var.env}/database/rds/credentials"
  description = "RDS database credentials with automatic rotation"
  
  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# 2. Store initial credentials (outside Terraform is better)
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id
  
  secret_string = jsonencode({
    username = "admin"
    password = "initial_password_change_me"
    host     = aws_db_instance.main.endpoint
    port     = 5432
    dbname   = "production_db"
  })
  
  lifecycle {
    ignore_changes = [secret_string]  # Prevent Terraform from overwriting rotations
  }
}

# ─────────────────────────────────────────────────────────────
# 3. Enable automatic rotation (every 30 days)
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret_rotation" "rds_credentials" {
  secret_id           = aws_secretsmanager_secret.rds_credentials.id
  rotation_lambda_arn = aws_lambda_function.rds_rotation.arn
  
  rotation_rules {
    automatically_after_days = 30  # Rotate every 30 days
  }
}

# ─────────────────────────────────────────────────────────────
# 4. Lambda function for rotation (AWS provides templates)
# ─────────────────────────────────────────────────────────────
# You can use AWS Serverless Application Repository (SAR) templates:
# arn:aws:serverlessrepo:us-east-1:297356227924:applications/SecretsManagerRDSPostgreSQLRotationSingleUser
```

---

### Using AWS-Managed Rotation (Easier Setup)

Instead of creating Lambda yourself, use **AWS Serverless Application Repository (SAR)**:

```bash
# Via AWS Console:
# 1. Go to Secrets Manager → Select secret
# 2. Click "Edit rotation"
# 3. Choose "Enable automatic rotation"
# 4. Select rotation schedule (30/60/90 days)
# 5. Choose "Create a new Lambda function" (AWS provides the code)
# 6. Select RDS instance
# 7. Save
```

AWS automatically:
- ✅ Creates a Lambda function with rotation logic
- ✅ Sets up IAM permissions
- ✅ Configures VPC access (if needed)
- ✅ Schedules rotation via EventBridge

---

### How Applications Handle Rotation

#### Option A: Fetch Secrets at Runtime (Recommended for Rotation)

Your app periodically fetches the secret, so it automatically gets the new value:

```typescript
let cachedSecrets: any;
let cacheExpiry = 0;

async function getDbCredentials() {
  // Refresh cache every 5 minutes
  if (cachedSecrets && Date.now() < cacheExpiry) {
    return cachedSecrets;
  }

  const result = await secretsManagerClient.send(
    new GetSecretValueCommand({ SecretId: "prod/database/rds/credentials" })
  );

  cachedSecrets = JSON.parse(result.SecretString!);
  cacheExpiry = Date.now() + 5 * 60 * 1000;  // Cache for 5 minutes
  
  return cachedSecrets;
}

// Use in DB connection pool
async function createDbConnection() {
  const creds = await getDbCredentials();
  return new Pool({
    host: creds.host,
    user: creds.username,
    password: creds.password,  // Automatically uses rotated password
    database: creds.dbname
  });
}
```

**Why this works:**
- App refetches secret every 5 minutes
- When rotation happens, next fetch gets new password
- Connection pool reconnects with new credentials automatically

#### Option B: Environment Variables (NOT Recommended for Rotation)

If secrets are injected as environment variables at container startup:
- ❌ Container must be **restarted** to get new values
- ❌ Rotation is **not seamless**
- ❌ Requires coordinated ECS task restarts

**Verdict:** Use Option A (runtime SDK fetch) if you enable rotation.

---

### Rotation vs. Versioning

Every secret has **multiple versions**:

| Version Stage | Purpose |
|---------------|---------|
| **AWSCURRENT** | The active version (what apps should use) |
| **AWSPENDING** | New version being created during rotation |
| **AWSPREVIOUS** | The previous version (rollback option) |

When you call `GetSecretValue` without specifying a version, you always get **AWSCURRENT**.

```bash
# Get current version (default)
aws secretsmanager get-secret-value \
  --secret-id prod/database/rds/credentials

# Get specific version by stage
aws secretsmanager get-secret-value \
  --secret-id prod/database/rds/credentials \
  --version-stage AWSPREVIOUS
```

---

### 💰 Rotation Cost Implications

| Component | Cost |
|-----------|------|
| **Secret storage** | $0.40/month (same whether rotated or not) |
| **Rotation API calls** | $0.05 per 10,000 calls (usually negligible) |
| **Lambda execution** | $0.20 per 1M requests + compute time (very cheap) |
| **KMS encryption** (if custom key) | $0.03 per 10,000 requests |

**Example: Monthly rotation of 10 secrets**
```
Secrets storage:       10 × $0.40           = $4.00
Rotation executions:   10 rotations/month   = ~$0.01
Total:                                      = ~$4.01/month
```

Rotation itself is **almost free**. The main cost is secret storage ($0.40/secret/month).

---

### 🔐 Security Benefits of Rotation

| Risk | Without Rotation | With Rotation (30 days) |
|------|------------------|-------------------------|
| **Compromised credentials** | Valid indefinitely | Valid for max 30 days |
| **Leaked in logs/code** | Permanent damage | Limited exposure window |
| **Insider threat** | Former employees retain access | Access automatically revoked |
| **Compliance** | Fails audit requirements | Meets SOC 2, PCI DSS, HIPAA |

---

### When to Enable Rotation

✅ **Enable rotation for:**
- Database credentials (RDS, Aurora, Redshift)
- Service account passwords
- API keys for critical services
- Credentials for compliance-regulated systems

❌ **Skip rotation for:**
- JWT signing secrets (requires coordinated app updates)
- Encryption keys (requires data re-encryption)
- Secrets that rarely change and have monitoring in place

---

### Summary: SSM Parameter Store vs Secrets Manager (Rotation)

| Feature | SSM Parameter Store | Secrets Manager |
|---------|---------------------|-----------------|
| **Automatic Rotation** | ❌ Not supported | ✅ Built-in with Lambda |
| **Manual Updates** | ✅ You update via CLI/API | ✅ You update via CLI/API |
| **Versioning** | ✅ Basic (latest only) | ✅ Advanced (AWSCURRENT, AWSPENDING, AWSPREVIOUS) |
| **Rotation Lambda** | ❌ You must build everything | ✅ AWS provides for RDS/Aurora/Redshift/DocumentDB |
| **Cost** | Free (standard tier) | $0.40/secret/month + API calls |

**Verdict:** If you need **automatic rotation**, use Secrets Manager. If credentials are **static or manually managed**, SSM Parameter Store is cheaper.

---

## 🎯 Real-World Example: MySQL Database Rotation on EC2

### Scenario

You have:
- **MySQL database** running in a Docker container on an EC2 instance
- **Private IP**: `10.0.1.5`
- **Port**: `3306`
- **Secret name**: `/myapp/db_credentials`
- **Rotation frequency**: Every **5 days**
- **Initial setup**: Values set via AWS Console UI (not Terraform)
- **Terraform role**: Manage infrastructure only, not secret values

---

### Step 1: Create Secret Infrastructure (Terraform)

**File: `modules/secret_manager/main.tf`**

```hcl
# ─────────────────────────────────────────────────────────────
# Create the secret (NO default value)
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.env}/myapp/db_credentials"
  description = "MySQL database credentials with 5-day rotation"
  
  tags = {
    Environment = var.env
    Application = "myapp"
    Database    = "mysql-ec2"
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# Enable automatic rotation (every 5 days)
# ─────────────────────────────────────────────────────────────
resource "aws_secretsmanager_secret_rotation" "db_credentials" {
  secret_id           = aws_secretsmanager_secret.db_credentials.id
  rotation_lambda_arn = aws_lambda_function.mysql_rotation.arn
  
  rotation_rules {
    automatically_after_days = 5  # Rotate every 5 days
  }
}

# ─────────────────────────────────────────────────────────────
# Lambda function for MySQL rotation (custom implementation)
# ─────────────────────────────────────────────────────────────
resource "aws_lambda_function" "mysql_rotation" {
  function_name = "${var.env}-mysql-rotation-lambda"
  role          = aws_iam_role.lambda_rotation.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  timeout       = 30
  
  filename         = "${path.module}/lambda/mysql-rotation.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda/mysql-rotation.zip")
  
  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com"
    }
  }
  
  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_rotation.id]
  }
  
  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# Security Group for Lambda (allow MySQL access)
# ─────────────────────────────────────────────────────────────
resource "aws_security_group" "lambda_rotation" {
  name        = "${var.env}-mysql-rotation-lambda-sg"
  description = "Allow Lambda to connect to MySQL on EC2"
  vpc_id      = var.vpc_id
  
  egress {
    description = "MySQL access to EC2 instance"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.5/32"]  # Your MySQL EC2 instance
  }
  
  egress {
    description = "HTTPS for Secrets Manager API"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name        = "${var.env}-mysql-rotation-lambda-sg"
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# ─────────────────────────────────────────────────────────────
# IAM Role for Lambda Rotation Function
# ─────────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda_rotation" {
  name = "${var.env}-mysql-rotation-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = {
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

# Attach AWS managed policy for VPC access
resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_rotation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Custom policy for Secrets Manager access
resource "aws_iam_role_policy" "lambda_secrets_access" {
  name = "secrets-manager-rotation-access"
  role = aws_iam_role.lambda_rotation.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:DescribeSecret",
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetRandomPassword"
        ]
        Resource = "*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────────────
# Grant Secrets Manager permission to invoke Lambda
# ─────────────────────────────────────────────────────────────
resource "aws_lambda_permission" "allow_secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mysql_rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}
```

---

### Step 2: Create Lambda Rotation Function

**File: `modules/secret_manager/lambda/mysql-rotation/index.py`**

```python
import json
import boto3
import pymysql
import os
from botocore.exceptions import ClientError

# Initialize AWS clients
secrets_client = boto3.client('secretsmanager')

def handler(event, context):
    """
    AWS Secrets Manager rotation handler for MySQL
    
    Args:
        event: Lambda event containing:
            - SecretId: ARN of the secret
            - Token: Rotation token (version ID)
            - Step: One of createSecret, setSecret, testSecret, finishSecret
    """
    
    secret_arn = event['SecretId']
    token = event['Token']
    step = event['Step']
    
    print(f"Rotation step: {step} for secret: {secret_arn}")
    
    # Dispatch to the appropriate step handler
    if step == "createSecret":
        create_secret(secret_arn, token)
    elif step == "setSecret":
        set_secret(secret_arn, token)
    elif step == "testSecret":
        test_secret(secret_arn, token)
    elif step == "finishSecret":
        finish_secret(secret_arn, token)
    else:
        raise ValueError(f"Invalid step: {step}")


def create_secret(secret_arn, token):
    """Generate a new password and store it with AWSPENDING stage"""
    
    # Get current secret value (AWSCURRENT)
    current_secret = get_secret_value(secret_arn, "AWSCURRENT")
    
    # Check if AWSPENDING version already exists
    try:
        get_secret_value(secret_arn, "AWSPENDING", token)
        print(f"Secret version {token} already exists with AWSPENDING stage")
        return
    except ClientError:
        pass  # Expected if version doesn't exist
    
    # Generate new password
    passwd_response = secrets_client.get_random_password(
        PasswordLength=32,
        ExcludeCharacters='/@"\'\\'  # Exclude chars that might cause MySQL issues
    )
    new_password = passwd_response['RandomPassword']
    
    # Create new secret version with AWSPENDING stage
    new_secret = current_secret.copy()
    new_secret['db_password'] = new_password
    
    secrets_client.put_secret_value(
        SecretId=secret_arn,
        ClientRequestToken=token,
        SecretString=json.dumps(new_secret),
        VersionStages=['AWSPENDING']
    )
    
    print(f"Created new secret version {token} with AWSPENDING stage")


def set_secret(secret_arn, token):
    """Update the MySQL database password with the new value"""
    
    # Get current and pending secrets
    current_secret = get_secret_value(secret_arn, "AWSCURRENT")
    pending_secret = get_secret_value(secret_arn, "AWSPENDING", token)
    
    # Connect to MySQL using CURRENT credentials
    connection = pymysql.connect(
        host=current_secret.get('host', '10.0.1.5'),
        port=int(current_secret.get('port', 3306)),
        user=current_secret['db_username'],
        password=current_secret['db_password'],
        connect_timeout=5
    )
    
    try:
        with connection.cursor() as cursor:
            # Update password in MySQL
            username = current_secret['db_username']
            new_password = pending_secret['db_password']
            
            # MySQL 8.0+ syntax
            cursor.execute(
                "ALTER USER %s@'%%' IDENTIFIED BY %s",
                (username, new_password)
            )
            cursor.execute("FLUSH PRIVILEGES")
        
        connection.commit()
        print(f"Successfully updated MySQL password for user: {username}")
        
    finally:
        connection.close()


def test_secret(secret_arn, token):
    """Test that the new password works"""
    
    pending_secret = get_secret_value(secret_arn, "AWSPENDING", token)
    
    # Try to connect with new credentials
    connection = pymysql.connect(
        host=pending_secret.get('host', '10.0.1.5'),
        port=int(pending_secret.get('port', 3306)),
        user=pending_secret['db_username'],
        password=pending_secret['db_password'],
        connect_timeout=5
    )
    
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            result = cursor.fetchone()
            if result[0] != 1:
                raise ValueError("Test query failed")
        
        print("Successfully tested new credentials")
        
    finally:
        connection.close()


def finish_secret(secret_arn, token):
    """Move AWSCURRENT stage to the new version"""
    
    # Get current version
    metadata = secrets_client.describe_secret(SecretId=secret_arn)
    current_version = None
    
    for version_id, stages in metadata['VersionIdsToStages'].items():
        if 'AWSCURRENT' in stages:
            if version_id == token:
                print(f"Version {token} already marked as AWSCURRENT")
                return
            current_version = version_id
            break
    
    # Update version stages
    secrets_client.update_secret_version_stage(
        SecretId=secret_arn,
        VersionStage='AWSCURRENT',
        MoveToVersionId=token,
        RemoveFromVersionId=current_version
    )
    
    print(f"Successfully moved AWSCURRENT stage to version {token}")


def get_secret_value(secret_arn, stage, version_id=None):
    """Retrieve secret value for a specific stage"""
    
    params = {
        'SecretId': secret_arn,
        'VersionStage': stage
    }
    
    if version_id:
        params['VersionId'] = version_id
    
    response = secrets_client.get_secret_value(**params)
    return json.loads(response['SecretString'])
```

**File: `modules/secret_manager/lambda/mysql-rotation/requirements.txt`**

```
pymysql==1.1.0
boto3>=1.28.0
```

---

### Step 3: Package Lambda Function

Create the Lambda deployment package:

```bash
cd modules/secret_manager/lambda/mysql-rotation

# Create virtual environment and install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt -t .

# Create deployment package
zip -r ../mysql-rotation.zip index.py pymysql/ boto3/ botocore/ *

deactivate
```

---

### Step 4: Deploy Infrastructure with Terraform

```bash
# Initialize and plan
terraform init
terraform plan

# Deploy
terraform apply

# Output will show:
# - Secret ARN: arn:aws:secretsmanager:eu-west-2:xxxxx:secret:/myapp/db_credentials
# - Lambda ARN: arn:aws:lambda:eu-west-2:xxxxx:function:staging-mysql-rotation-lambda
# - Rotation enabled: Every 5 days
```

**Important:** At this point, the secret exists but **has no value** yet.

---

### Step 5: Set Initial Secret Value (AWS Console UI)

1. **Go to AWS Console** → Secrets Manager
2. **Find your secret**: `staging/myapp/db_credentials` (or your environment prefix)
3. **Click "Retrieve secret value"** → Click "Edit"
4. **Set the initial value as JSON**:

```json
{
  "db_username": "sample_user1",
  "db_password": "sample_password",
  "host": "10.0.1.5",
  "port": 3306,
  "database": "myapp_db"
}
```

5. **Click "Save"**

**Alternative: Using AWS CLI**

```bash
aws secretsmanager put-secret-value \
  --secret-id staging/myapp/db_credentials \
  --secret-string '{
    "db_username": "sample_user1",
    "db_password": "sample_password",
    "host": "10.0.1.5",
    "port": 3306,
    "database": "myapp_db"
  }'
```

---

### Step 6: Create MySQL User with Self-Password Update Privileges (On EC2 Instance)

⚠️ **CRITICAL REQUIREMENT**: The user must have permission to **update their own password**, otherwise rotation will fail!

SSH into your EC2 instance and create the MySQL user:

```bash
# Connect to EC2
ssh user@ec2-instance

# Access MySQL container
docker exec -it mysql-container mysql -u root -p

# In MySQL prompt:
CREATE USER 'sample_user1'@'%' IDENTIFIED BY 'sample_password';

# Grant application permissions
GRANT ALL PRIVILEGES ON myapp_db.* TO 'sample_user1'@'%';

# ⚠️ CRITICAL: Grant permission to update own password
# Without this, the Lambda rotation function will fail!
GRANT ALTER USER ON *.* TO 'sample_user1'@'%';

# Alternative for MySQL 5.7 (if ALTER USER doesn't work):
# GRANT CREATE USER ON *.* TO 'sample_user1'@'%';

FLUSH PRIVILEGES;
EXIT;
```

**Important Notes:**

1. **Password must match**: The initial password here (`sample_password`) must match what you set in Secrets Manager.

2. **ALTER USER privilege**: Required for MySQL 8.0+ to allow the user to execute `ALTER USER 'sample_user1'@'%' IDENTIFIED BY 'new_password'` on themselves.

3. **CREATE USER privilege** (MySQL 5.7): Older MySQL versions may require `CREATE USER` privilege instead of `ALTER USER`.

4. **Security consideration**: `ALTER USER ON *.*` allows the user to change their own password but NOT other users' passwords (when they execute `ALTER USER 'sample_user1'@'%'...` it only affects themselves).

---

#### Alternative Approach: Use a Separate Admin User for Rotation

If you don't want to grant `ALTER USER` to the application user, use a **separate admin user** for rotation:

**Step 6a: Create Two Users**

```sql
-- Application user (no ALTER USER privilege)
CREATE USER 'sample_user1'@'%' IDENTIFIED BY 'sample_password';
GRANT ALL PRIVILEGES ON myapp_db.* TO 'sample_user1'@'%';

-- Rotation admin user (has ALTER USER privilege)
CREATE USER 'rotation_admin'@'%' IDENTIFIED BY 'admin_secure_password';
GRANT ALTER USER ON *.* TO 'rotation_admin'@'%';

FLUSH PRIVILEGES;
```

**Step 6b: Store Admin Credentials in Separate Secret**

```bash
# Create admin secret (not rotated)
aws secretsmanager create-secret \
  --name staging/myapp/rotation_admin_credentials \
  --secret-string '{
    "username": "rotation_admin",
    "password": "admin_secure_password"
  }'
```

**Step 6c: Modify Lambda to Use Admin Credentials**

Update the `set_secret()` function in your Lambda:

```python
def set_secret(secret_arn, token):
    """Update the MySQL database password using admin credentials"""
    
    # Get admin credentials (for connecting)
    admin_secret = secrets_client.get_secret_value(
        SecretId='staging/myapp/rotation_admin_credentials'
    )
    admin_creds = json.loads(admin_secret['SecretString'])
    
    # Get current app user credentials
    current_secret = get_secret_value(secret_arn, "AWSCURRENT")
    pending_secret = get_secret_value(secret_arn, "AWSPENDING", token)
    
    # Connect using ADMIN credentials
    connection = pymysql.connect(
        host=current_secret.get('host', '10.0.1.5'),
        port=int(current_secret.get('port', 3306)),
        user=admin_creds['username'],        # ← Admin user
        password=admin_creds['password'],    # ← Admin password
        connect_timeout=5
    )
    
    try:
        with connection.cursor() as cursor:
            # Update APP USER's password
            app_username = current_secret['db_username']  # sample_user1
            new_password = pending_secret['db_password']
            
            cursor.execute(
                "ALTER USER %s@'%%' IDENTIFIED BY %s",
                (app_username, new_password)
            )
            cursor.execute("FLUSH PRIVILEGES")
        
        connection.commit()
        print(f"Admin successfully updated password for user: {app_username}")
        
    finally:
        connection.close()
```

**Pros of Admin User Approach:**
- ✅ Application user has minimal privileges (principle of least privilege)
- ✅ More secure (app user can't modify passwords)
- ✅ Cleaner separation of concerns

**Cons:**
- ❌ More complex setup (two users, two secrets)
- ❌ Admin password becomes a single point of failure (should also be rotated periodically)

---

#### Verify User Privileges

To check if the user has the correct privileges:

```sql
-- Show all privileges for the user
SHOW GRANTS FOR 'sample_user1'@'%';

-- Expected output should include:
-- GRANT ALTER USER ON *.* TO `sample_user1`@`%`
-- OR
-- GRANT CREATE USER ON *.* TO `sample_user1`@`%` (MySQL 5.7)
```

---

#### What Happens If Privileges Are Missing?

If the user lacks `ALTER USER` privilege, rotation will fail at the `setSecret` step:

**Lambda logs will show:**
```
[ERROR] pymysql.err.OperationalError: (1227, 'Access denied; you need (at least one of) the CREATE USER privilege(s) for this operation')
```

**Secrets Manager status:**
- Secret version remains in `AWSPENDING` stage
- `AWSCURRENT` keeps the old (working) password
- CloudWatch alarm triggers (if configured)
- Applications continue working with old password (no downtime)

**To fix:**
1. Grant the missing privilege to the user
2. Manually retry rotation: `aws secretsmanager rotate-secret --secret-id staging/myapp/db_credentials`

---

### Step 7: Test Manual Rotation (Optional)

Test rotation immediately without waiting 5 days:

```bash
aws secretsmanager rotate-secret \
  --secret-id staging/myapp/db_credentials
```

**Monitor rotation progress:**

```bash
# Check rotation status
aws secretsmanager describe-secret \
  --secret-id staging/myapp/db_credentials \
  --query 'RotationEnabled'

# Check Lambda logs
aws logs tail /aws/lambda/staging-mysql-rotation-lambda --follow
```

---

### Step 8: Configure Your Application

**Option A: ECS Task Definition (Environment Variable Injection)**

```hcl
resource "aws_ecs_task_definition" "app" {
  family = "myapp"
  
  execution_role_arn = module.ecs_task_execution_role.role_arn
  
  container_definitions = jsonencode([{
    name  = "app"
    image = "your-app:latest"
    
    secrets = [
      {
        name      = "DB_USERNAME"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:db_username::"
      },
      {
        name      = "DB_PASSWORD"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:db_password::"
      },
      {
        name      = "DB_HOST"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:host::"
      },
      {
        name      = "DB_PORT"
        valueFrom = "${aws_secretsmanager_secret.db_credentials.arn}:port::"
      }
    ]
  }])
}
```

**Grant Task Execution Role permission:**

```hcl
resource "aws_iam_role_policy" "task_execution_secrets" {
  role = module.ecs_task_execution_role.role_name
  
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}
```

**Option B: Runtime Fetch (Recommended for Rotation)**

```javascript
// app.js
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({ region: 'eu-west-2' });
let cachedCredentials = null;
let cacheExpiry = 0;

async function getDbCredentials() {
  // Refresh every 5 minutes to handle rotation
  if (cachedCredentials && Date.now() < cacheExpiry) {
    return cachedCredentials;
  }
  
  const result = await client.send(
    new GetSecretValueCommand({ SecretId: 'staging/myapp/db_credentials' })
  );
  
  cachedCredentials = JSON.parse(result.SecretString);
  cacheExpiry = Date.now() + 5 * 60 * 1000;  // 5 minutes
  
  return cachedCredentials;
}

// Use in connection pool
const mysql = require('mysql2/promise');

async function createDbPool() {
  const creds = await getDbCredentials();
  
  return mysql.createPool({
    host: creds.host,
    port: creds.port,
    user: creds.db_username,
    password: creds.db_password,
    database: creds.database,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0
  });
}

module.exports = { createDbPool, getDbCredentials };
```

**Grant Task Role permission:**

```hcl
resource "aws_iam_role_policy" "task_secrets_access" {
  role = module.ecs_task_role.role_name
  
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.db_credentials.arn
    }]
  })
}
```

---

### Step 9: Monitor Rotation

**CloudWatch Metrics:**

```bash
# View rotation success/failure metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SecretsManager \
  --metric-name RotationSucceeded \
  --dimensions Name=SecretId,Value=staging/myapp/db_credentials \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-31T23:59:59Z \
  --period 86400 \
  --statistics Sum
```

**Set up CloudWatch Alarm for Failed Rotations:**

```hcl
resource "aws_cloudwatch_metric_alarm" "rotation_failure" {
  alarm_name          = "${var.env}-mysql-rotation-failure"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RotationFailed"
  namespace           = "AWS/SecretsManager"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when MySQL secret rotation fails"
  
  dimensions = {
    SecretId = aws_secretsmanager_secret.db_credentials.id
  }
  
  alarm_actions = [var.sns_topic_arn]  # Your SNS topic for alerts
}
```

---

### Rotation Timeline Example

```
Day 0 (Initial Setup):
  - Terraform creates secret infrastructure
  - You set initial value via AWS Console
  - Password: "sample_password"

Day 5 (First Rotation):
  - EventBridge triggers rotation
  - Lambda generates new password: "aB3$xYz9..."
  - Lambda updates MySQL user password
  - Lambda tests new credentials
  - Secret version promoted to AWSCURRENT
  - Old password still accessible via AWSPREVIOUS

Day 10 (Second Rotation):
  - Process repeats
  - New password: "kL7#mNp2..."
  - Previous password from Day 5 becomes AWSPREVIOUS

Your app:
  - Fetches secret every 5 minutes
  - Automatically gets new password after rotation
  - Connection pool reconnects seamlessly
```

---

### Important Notes

1. **Terraform State**: Secret **structure** is in Terraform state, **values** are not (since you set them in UI)

2. **Rotation Timing**: Rotation happens **within a 4-hour window** on the 5th day (not exactly at midnight)

3. **Network Access**: Lambda must be in a subnet with route to `10.0.1.5:3306`

4. **Security Group**: EC2 MySQL instance must allow inbound from Lambda security group

5. **VPC Endpoints**: If Lambda is in private subnet without NAT Gateway, add VPC endpoint for Secrets Manager:

```hcl
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id             = var.vpc_id
  service_name       = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
}
```

6. **Cost**: $0.40/month for secret + ~$0.01/month for Lambda executions = **$0.41/month**

---

### Troubleshooting

**Rotation fails with "Access denied for user":**
- Check MySQL user exists and has `%` host wildcard
- Verify current password in Secrets Manager matches MySQL
- Check Lambda can reach `10.0.1.5:3306` (security groups)

**Lambda timeout:**
- Increase Lambda timeout to 60 seconds
- Check VPC route table allows access to EC2 instance
- Verify subnet has NAT Gateway or VPC endpoint for Secrets Manager API

**Terraform apply overwrites secret value:**
- Never create `aws_secretsmanager_secret_version` in Terraform
- Only create `aws_secretsmanager_secret` (structure only)

**Application still uses old password:**
- Check app is fetching secrets at runtime (not using environment variables)
- Reduce cache TTL from 5 minutes to 1 minute during testing
- Verify Task Role has `secretsmanager:GetSecretValue` permission

---

## 🔐 IAM Roles in ECS (Critical Distinction)

| Role                    | Purpose                                                |
| ----------------------- | ------------------------------------------------------ |
| **Task Execution Role** | Used by ECS to pull images, inject secrets, write logs |
| **Task Role**           | Used by the application code to access AWS services    |

> ⚠️ Never confuse these roles. They serve different purposes.

---

## ✅ Option 1 — ECS Injects Secrets as Environment Variables

### How it Works

1. Secret is stored in AWS Secrets Manager
2. ECS Task Definition references the secret ARN
3. ECS fetches the secret **at task startup**
4. Secret is injected as an environment variable

The application reads it like any normal env var.

---

### IAM Requirements

* Permission required: `secretsmanager:GetSecretValue`
* **Role**: Task Execution Role
* Used **only during task startup**

---

### Terraform Example

```hcl
secrets = [
  {
    name      = "DB_PASSWORD"
    valueFrom = aws_secretsmanager_secret.db_password.arn
  }
]
```

---

### Runtime Behavior

* Secrets are read **once** at container startup
* Updating the secret in AWS **does NOT update running tasks**
* New tasks receive the updated value

To apply updates:

* redeploy ECS service
* restart tasks
* or trigger a scaling event

---

### When to Use Option 1

✔️ Static secrets (JWT secret, DB password)
✔️ Simpler setup
✔️ No runtime AWS SDK calls

---

## ✅ Option 2 — Application Fetches Secrets via AWS SDK

### How it Works

1. ECS assigns a **Task Role** to the task
2. AWS exposes a **task-scoped metadata endpoint**
3. AWS SDK fetches temporary credentials automatically
4. App calls Secrets Manager at runtime

No credentials are hard-coded or injected.

---

### Authentication Model (Important)

* No static credentials exist in the container
* The metadata endpoint is authenticated by **network isolation**
* Temporary IAM credentials are returned
* AWS SDK signs all API requests automatically

---

### IAM Requirements

* Permission required: `secretsmanager:GetSecretValue`
* **Role**: Task Role
* Scope permissions to specific secret ARNs

---

### Node.js Example

```ts
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";

const client = new SecretsManagerClient({});

async function fetchSecrets() {
    const result = await client.send(
        new GetSecretValueCommand({ SecretId: "prod/app-config" })
    );

    return JSON.parse(result.SecretString!);
}
```

---

### Fetch Frequency & Caching (Best Practice)

* Fetch secrets **once at startup**
* Cache in memory
* Refresh periodically (e.g. every 5 minutes)

Example pattern:

```ts
let cachedSecrets: any;
let expiresAt = 0;

async function getSecrets() {
  if (cachedSecrets && Date.now() < expiresAt) return cachedSecrets;

  const res = await client.send(
    new GetSecretValueCommand({ SecretId: "prod/app-config" })
  );

  cachedSecrets = JSON.parse(res.SecretString!);
  expiresAt = Date.now() + 5 * 60 * 1000;
  return cachedSecrets;
}
```

---

### Runtime Behavior

* Secrets can be updated without restarting containers
* Next fetch returns the new value
* Ideal for rotated credentials

---

### When to Use Option 2

✔️ Rotating secrets
✔️ Dynamic credentials (RDS, API tokens)
✔️ Zero-restart updates

---

## ❌ Common Mistakes to Avoid

* Using execution role for runtime access
* Fetching secrets on every request
* Storing secrets in GitHub or Docker images
* Using `secretsmanager:*` permissions
* Logging secret values

---

## 🔁 Comparison Summary

| Feature          | Option 1  | Option 2 |
| ---------------- | --------- | -------- |
| Read time        | Startup   | Runtime  |
| IAM role         | Execution | Task     |
| App code         | None      | Required |
| Rotation support | ❌         | ✅        |
| Complexity       | Low       | Medium   |

---

## 🏆 Recommended Strategy

* Use **Option 1 (ECS secret injection)** as the default approach
* Terraform manages **secret infrastructure**, not secret values
* Secret values are managed **outside Terraform** (UI / CLI / rotation)
* Use **Option 2** only when runtime rotation without restart is required
* Terraform manages **secret infrastructure**, not secret values
* Secret values are managed **outside Terraform** (UI / CLI / rotation)

---

## 🧱 Terraform & Secrets: Source of Truth Rules (Important)

### The Rule

> **Terraform must never be the long-term source of truth for secret values.**

If Terraform manages the secret value and it is later edited in the AWS Console:

* the change is considered **drift**
* the next `terraform apply` will **reset the value**

---

### ✅ Best Practice (Recommended)

Terraform should:

* create the secret
* manage metadata (name, description, KMS key)
* manage IAM access

Terraform should **NOT**:

* manage secret values

```hcl
resource "aws_secretsmanager_secret" "app_config" {
  name = "prod/app-config"
}
```

Secret values are then:

* set initially via AWS Console or CLI
* rotated manually or automatically
* never overwritten by Terraform

---

### ⚠️ Acceptable Alternative (Use with Caution)

If an initial value must be set via Terraform:

```hcl
resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id     = aws_secretsmanager_secret.app_config.id
  secret_string = var.initial_secret

  lifecycle {
    ignore_changes = [secret_string]
  }
}
```

This:

* creates the value once
* prevents Terraform from overwriting future changes
* still stores the secret in Terraform state

---

### ❌ Anti-Patterns (Avoid)

* Editing secrets in the UI while Terraform manages the value
* Storing secrets directly in Terraform variables
* Committing secret values to Git
* Letting CI logs expose secrets

---

### 🧠 Final Guidance

* **Infrastructure is declarative → Terraform**
* **Secrets are operational → Secrets Manager UI / automation**

This separation prevents accidental rollbacks and supports safe scaling and rotation.

---

This document should be used as the **reference guide** for secrets handling across all environments.
