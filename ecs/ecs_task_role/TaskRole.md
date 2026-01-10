# ECS Task Role Module

## Overview

This module creates an **IAM role** that grants your **application code** (running inside ECS containers) permissions to access AWS services.

Unlike the **Task Execution Role** (which is used by the ECS service itself), this role is assumed by your application at runtime to interact with AWS APIs.

---

## What Does This Role Do?

This role allows your containerized application to:
- **Access S3 buckets** (upload/download files)
- **Read/write to DynamoDB tables**
- **Send emails via SES**
- **Publish messages to SNS/SQS**
- **Read secrets from AWS Secrets Manager or Parameter Store** (when accessed from application code)
- **Call other AWS services** your application needs

**Important**: This role is **optional**. Only create it if your application needs to call AWS APIs. If your app just serves HTTP requests without AWS SDK calls, you don't need a task role.

---

Environment	Authentication method
Local dev	Access keys / profiles
EC2	Instance role
ECS	Task role (temporary credentials)
Lambda	Execution role

## Common Permissions This Role Can Grant

| AWS Service | Use Case | Actions Needed | When to Use |
|-------------|----------|----------------|-------------|
| **S3** | Upload/download files | `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` | File storage, document uploads, static assets |
| **DynamoDB** | NoSQL database operations | `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:Query`, `dynamodb:Scan` | Session storage, user data, real-time data |
| **RDS/Aurora** | Relational database auth | `rds-db:connect` | Connecting to RDS with IAM authentication |
| **SES** | Send emails | `ses:SendEmail`, `ses:SendRawEmail` | Transactional emails, notifications |
| **SNS** | Publish messages/notifications | `sns:Publish` | Push notifications, event broadcasting |
| **SQS** | Queue operations | `sqs:SendMessage`, `sqs:ReceiveMessage`, `sqs:DeleteMessage` | Asynchronous job processing, decoupling services |
| **Secrets Manager** | Read app secrets at runtime | `secretsmanager:GetSecretValue` | API keys, DB passwords (accessed via SDK in code) |
| **SSM Parameter Store** | Read app parameters at runtime | `ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParametersByPath` | Configuration values, feature flags (accessed via SDK in code) |
| **CloudWatch Logs** | Custom application logging | `logs:CreateLogStream`, `logs:PutLogEvents` | Additional logging beyond default container logs |
| **Lambda** | Invoke other functions | `lambda:InvokeFunction` | Microservice orchestration |
| **EventBridge** | Put custom events | `events:PutEvents` | Custom event-driven workflows |
| **Kinesis** | Stream data processing | `kinesis:PutRecord`, `kinesis:GetRecords` | Real-time data streaming |
| **ECR** | Pull images (rarely needed) | `ecr:GetAuthorizationToken`, `ecr:BatchGetImage` | Only if app pulls additional images at runtime |
| **CloudFront** | Invalidate cache | `cloudfront:CreateInvalidation` | CDN cache management |
| **Route53** | DNS operations | `route53:ChangeResourceRecordSets` | Dynamic DNS updates |

### ⚠️ Important: Secrets Access - Task Role vs Task Execution Role

**There are TWO ways to access secrets in ECS:**

| Method | When Used | Which Role Needs Permission |
|--------|-----------|----------------------------|
| **1. Container Environment Variables** (at startup) | Secret injected as environment variable when container starts | **Task Execution Role** |
| **2. Application Code** (at runtime) | App calls AWS SDK to fetch secret while running | **Task Role** |

#### Example 1: Secrets in Environment Variables (Task Execution Role)

```hcl
# Task definition with secret as environment variable
container_definitions = jsonencode([{
  name  = "ecs-node-app"
  image = "..."
  secrets = [
    {
      name      = "DB_PASSWORD"
      valueFrom = "arn:aws:secretsmanager:eu-west-2:123456789:secret:prod/db/password"
    }
  ]
}])

# Task EXECUTION role needs this permission
resource "aws_iam_role_policy" "secrets_access" {
  role = module.ecs_task_execution_role.role_name  # ← EXECUTION role
  
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:eu-west-2:123456789:secret:prod/db/*"
    }]
  })
}
```

**Your app accesses it like a normal environment variable:**
```javascript
const dbPassword = process.env.DB_PASSWORD; // Available at startup
```

#### Example 2: Secrets Fetched by Application Code (Task Role)

```hcl
# Task ROLE needs this permission (not execution role)
resource "aws_iam_role_policy" "app_secrets_access" {
  role = module.ecs_task_role.role_name  # ← TASK role (this module)
  
  policy = jsonencode({
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:eu-west-2:123456789:secret:app/api-keys/*"
    }]
  })
}
```

**Your app fetches secrets at runtime using AWS SDK:**
```javascript
const { SecretsManagerClient, GetSecretValueCommand } = require('@aws-sdk/client-secrets-manager');

const client = new SecretsManagerClient({ region: 'eu-west-2' });

async function getApiKey() {
  const command = new GetSecretValueCommand({
    SecretId: 'app/api-keys/stripe'
  });
  
  const response = await client.send(command);
  return JSON.parse(response.SecretString);
}
```

**Summary:**
- **Secrets injected at container startup** → Task Execution Role needs permission
- **Secrets fetched by app code while running** → Task Role needs permission

---

## Usage in Your Infrastructure

### In Staging

```hcl
module "ecs_task_role" {
  source = "../../staging-infrastructure/modules/ecs_task_role"
  
  env        = var.env         # e.g., "staging"
  project_id = var.project_id  # e.g., "cerpac"
}

# Reference in task definition
resource "aws_ecs_task_definition" "node_app" {
  task_role_arn = module.ecs_task_role.role_arn
  # ... rest of task definition
}
```

### In Production

```hcl
module "ecs_task_role" {
  source = "../../production-infrastructure/modules/ecs_task_role"
  
  env        = "production"
  project_id = "cerpac"
}
```

---

## Inputs

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `env` | string | Yes | - | Environment name (e.g., staging, production) |
| `project_id` | string | Yes | - | Project identifier (used in resource naming) |

---

## Outputs

| Output | Description | Example Value |
|--------|-------------|---------------|
| `role_arn` | The ARN of the created IAM role | `arn:aws:iam::820242908282:role/staging-ecs-task-role` |
| `role_name` | The name of the IAM role | `staging-ecs-task-role` |

---

## Default Permissions

By default, this module creates a **minimal role** with only the trust policy (no permissions). You need to attach additional policies based on your application's needs.

### Trust Policy (Who Can Assume This Role)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

This allows ECS tasks to assume the role and obtain temporary credentials.

---

## Adding Permissions to Your Task Role

### Example 1: Grant S3 Access

If your application uploads files to S3:

```hcl
module "ecs_task_role" {
  source     = "./modules/ecs_task_role"
  env        = "staging"
  project_id = "cerpac"
}

# Attach S3 access policy
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-access"
  role = module.ecs_task_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = "arn:aws:s3:::staging-cerpac-uploads/*"
      }
    ]
  })
}
```

### Example 2: Grant SES Email Sending

If your app sends emails:

```hcl
resource "aws_iam_role_policy" "ses_send" {
  name = "ses-send-email"
  role = module.ecs_task_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}
```

### Example 3: Grant DynamoDB Access

If your app reads/writes to DynamoDB:

```hcl
resource "aws_iam_role_policy" "dynamodb_access" {
  name = "dynamodb-access"
  role = module.ecs_task_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/staging-*"
      }
    ]
  })
}
```

### Example 4: Grant SSM Parameter Store Access (Runtime Fetch)

If your app fetches configuration parameters at runtime via SDK:

```hcl
resource "aws_iam_role_policy" "parameter_store_access" {
  name = "parameter-store-access"
  role = module.ecs_task_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/staging/myapp/*"
      }
    ]
  })
}
```

**Note:** This is for fetching parameters **at runtime via SDK**. If parameters are injected as environment variables in the task definition (using the `secrets` field), the **Task Execution Role** needs this permission instead.

**Application code example:**

```javascript
const { SSMClient, GetParameterCommand, GetParametersByPathCommand } = require('@aws-sdk/client-ssm');

const client = new SSMClient({ region: 'eu-west-2' });

// Get single parameter
async function getFeatureFlag() {
  const result = await client.send(
    new GetParameterCommand({ 
      Name: '/staging/myapp/features/enable_new_ui' 
    })
  );
  
  return result.Parameter.Value === 'true';
}

// Get all parameters in a path
async function getAllConfig() {
  const result = await client.send(
    new GetParametersByPathCommand({ 
      Path: '/staging/myapp/config',
      Recursive: true
    })
  );
  
  const config = {};
  result.Parameters.forEach(param => {
    const key = param.Name.split('/').pop();
    config[key] = param.Value;
  });
  
  return config;
}
```

---

## Difference: Task Role vs Task Execution Role

| Aspect | Task Role (This Module) | Task Execution Role |
|--------|-------------------------|---------------------|
| **Who uses it?** | Your application code | ECS service (AWS infrastructure) |
| **When is it used?** | While the container is running | During task startup (pull image, fetch secrets) |
| **Example permissions** | Access S3, DynamoDB, SES, SNS | Pull from ECR, write CloudWatch logs |
| **Required?** | **Optional** (only if your app needs AWS API access) | **Yes** (for Fargate) |
| **How app uses it** | Via AWS SDK (boto3, aws-sdk, etc.) | Transparent (ECS uses it automatically) |

---

## Complete Example: Using Both Roles

```hcl
# ─────────────────────────────────────────────────────
# 1. Task Execution Role (for ECS infrastructure)
# ─────────────────────────────────────────────────────
module "ecs_task_execution_role" {
  source     = "./modules/ecs_task_execution_role"
  env        = "staging"
  project_id = "cerpac"
}

# ─────────────────────────────────────────────────────
# 2. Task Role (for application permissions)
# ─────────────────────────────────────────────────────
module "ecs_task_role" {
  source     = "./modules/ecs_task_role"
  env        = "staging"
  project_id = "cerpac"
}

# Grant S3 access to the application
resource "aws_iam_role_policy" "app_s3_access" {
  name = "s3-upload-access"
  role = module.ecs_task_role.role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject"]
        Resource = "arn:aws:s3:::staging-cerpac-uploads/*"
      }
    ]
  })
}

# ─────────────────────────────────────────────────────
# 3. Task Definition Using Both Roles
# ─────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "node_app" {
  family = "staging-ecs-node-app-task"
  
  # ECS uses this to pull images and write logs
  execution_role_arn = module.ecs_task_execution_role.role_arn
  
  # Your app uses this to call AWS APIs
  task_role_arn = module.ecs_task_role.role_arn
  
  container_definitions = jsonencode([{
    name  = "ecs-node-app"
    image = "820242908282.dkr.ecr.eu-west-2.amazonaws.com/ecs-node-app:latest"
    # ... rest of config
  }])
}
```

---

## How Your Application Uses This Role

### In Node.js (AWS SDK v3)

```javascript
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');

// No credentials needed! SDK automatically uses task role
const s3 = new S3Client({ region: 'eu-west-2' });

async function uploadFile(fileBuffer, fileName) {
  const command = new PutObjectCommand({
    Bucket: 'staging-cerpac-uploads',
    Key: fileName,
    Body: fileBuffer
  });
  
  await s3.send(command); // Uses task role automatically
}
```

### In Python (boto3)

```python
import boto3

# No credentials needed! boto3 automatically uses task role
s3 = boto3.client('s3', region_name='eu-west-2')

def upload_file(file_data, file_name):
    s3.put_object(
        Bucket='staging-cerpac-uploads',
        Key=file_name,
        Body=file_data
    )
```

**Key Point**: Your application code doesn't need to specify credentials. The AWS SDK automatically discovers and uses the task role's temporary credentials.

---

## Security Best Practices

### ✅ DO

- **Principle of Least Privilege**: Only grant permissions your app actually needs
- **Use Resource-Level Permissions**: Restrict access to specific S3 buckets, DynamoDB tables, etc.
- **Separate Roles per Environment**: Different roles for staging vs production
- **Regular Audits**: Review and remove unused permissions

### ❌ DON'T

- **Never use `"Resource": "*"`** unless absolutely necessary
- **Don't grant admin permissions** (`iam:*`, `s3:*` on all buckets)
- **Don't hardcode credentials** in your application (use this role instead!)
- **Don't share roles across unrelated applications**

---

## Troubleshooting

### Error: "User is not authorized to perform: iam:PassRole"

**Cause**: The IAM user/role deploying Terraform lacks permission to pass roles to ECS.

**Solution**: Add this policy to your Terraform execution role:
```json
{
  "Effect": "Allow",
  "Action": "iam:PassRole",
  "Resource": [
    "arn:aws:iam::*:role/staging-ecs-task-role",
    "arn:aws:iam::*:role/staging-ecs-task-execution-role"
  ]
}
```

### Error: "Access Denied" when application calls AWS API

**Cause**: Task role lacks the necessary permissions.

**Solution**: Attach a policy to the task role granting the required permissions (see examples above).

### How to Verify the Role is Working

From inside your running container:

```bash
# Check if credentials are available
curl http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI

# Should return JSON with AccessKeyId, SecretAccessKey, Token, Expiration
```

---

## Cost Considerations

- **IAM roles are FREE** - no charges for creating or using IAM roles
- **API calls made by your application** are charged based on the service (S3 requests, DynamoDB operations, etc.)

---

## Related Documentation

- [AWS ECS Task IAM Roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- [IAM Roles for Tasks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
- Task Execution Role Module: `modules/ecs_task_execution_role/`
- ECS Task Definition: `node_app_task_definition.tf`
- IAM Policy Examples: [AWS Policy Examples](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_examples.html)

---

## Tags Applied

All resources created by this module are tagged with:
- `Environment`: Value from `var.env`
- `ManagedBy`: `Terraform`
- `Module`: `ecs_task_role`

