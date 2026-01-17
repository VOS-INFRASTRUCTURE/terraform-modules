# IAM Modules

This directory contains reusable Terraform modules for AWS Identity and Access Management (IAM) related resources.

## Available Modules

### 1. Access Analyzer (`access_analyzer/`)

**Purpose:** Enable IAM Access Analyzer to identify resources shared with external entities and detect potential security risks.

**What it does:**
- Continuously monitors resource-based policies
- Identifies external access to S3 buckets, IAM roles, KMS keys, etc.
- Detects publicly accessible resources
- Generates findings for Security Hub integration
- Provides visibility into cross-account access

**Key Use Cases:**
- ✅ Prevent data leaks from misconfigured S3 buckets
- ✅ Audit cross-account IAM role assumptions
- ✅ Detect publicly accessible resources
- ✅ Comply with Security Hub IAM.21 control
- ✅ Meet GDPR/PCI DSS data access auditing requirements

**Cost:** FREE (standard account-level analyzer)

**Security Hub Control:** IAM.21 - "IAM Access Analyzer should be enabled"

**Example:**
```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "myapp"
  enable_access_analyzer = true
  analyzer_type          = "ACCOUNT"  # or "ORGANIZATION"
}
```

### 2. ECS IAM CI/CD User (`ecs_iam_cicd_user/`)

**Purpose:** Create dedicated IAM users with least-privilege permissions for CI/CD pipelines (GitHub Actions, GitLab CI, etc.) to deploy to ECS.

**What it does:**
- Creates IAM user for automated deployments
- Grants permissions for ECR push/pull
- Allows ECS service updates and task definition registration
- Provides CloudWatch Logs read access
- Generates access keys for CI/CD secrets

**Key Use Cases:**
- ✅ GitHub Actions ECS deployment automation
- ✅ GitLab CI/CD pipeline authentication
- ✅ Jenkins ECS deployment jobs
- ✅ Least-privilege CI/CD access

**Security Features:**
- Scoped to specific ECS service and ECR repository
- No infrastructure modification permissions
- Separate from Terraform admin credentials
- Supports optional access key creation

**Example:**
```hcl
module "github_actions_cicd_user" {
  source = "../../iam/ecs_iam_cicd_user"

  env        = "staging"
  project_id = "cerpac"

  # ECS service to allow deployments to
  ecs_service_arn = "arn:aws:ecs:eu-west-2:123456789012:service/staging-cluster/staging-service"
  ecs_cluster_arn = "arn:aws:ecs:eu-west-2:123456789012:cluster/staging-cluster"

  # ECR repository to allow image push
  ecr_repository_arn = "arn:aws:ecr:eu-west-2:123456789012:repository/staging-app"

  # IAM roles to pass to ECS tasks
  ecs_task_execution_role_arn = "arn:aws:iam::123456789012:role/staging-task-execution-role"
  ecs_task_role_arn           = "arn:aws:iam::123456789012:role/staging-task-role"

  # CloudWatch log group for deployment verification
  cloudwatch_log_group_arn = "arn:aws:logs:eu-west-2:123456789012:log-group:/ecs/staging-app"

  # Create access key for GitHub Secrets
  create_access_key = true
}
```

## IAM Access Analyzer vs AWS Config

### Quick Comparison

| Aspect | IAM Access Analyzer | AWS Config |
|--------|-------------------|------------|
| **Focus** | "Who can access my resources?" | "Are resources configured correctly?" |
| **Analysis** | External access & permissions | Configuration compliance |
| **Findings** | Cross-account access, public exposure | Encryption, logging, tagging violations |
| **Cost** | Free | ~$0.003 per configuration item |
| **Use Together** | ✅ Recommended for complete security |

**Key Takeaway:** Use BOTH for comprehensive AWS security coverage!

## Best Practices

### IAM Access Analyzer
1. ✅ Enable in all AWS accounts (even dev/test)
2. ✅ Use `ORGANIZATION` type in management account for centralized visibility
3. ✅ Integrate findings with Security Hub for centralized alerts
4. ✅ Set up automated remediation for public access findings
5. ✅ Review findings regularly (weekly minimum)

### CI/CD IAM Users
1. ✅ One IAM user per CI/CD pipeline (separate staging/production)
2. ✅ Rotate access keys every 90 days
3. ✅ Store credentials in CI/CD secrets manager (GitHub Secrets, AWS Secrets Manager)
4. ✅ Never commit access keys to version control
5. ✅ Use least-privilege permissions (scope to specific services)
6. ✅ Enable CloudTrail to audit all API calls
7. ✅ Consider using OIDC instead of access keys (for GitHub Actions)

## Module Standards

All modules in this directory follow these standards:
- ✅ Optional resource creation via `enable_*` variables
- ✅ Environment and project tagging
- ✅ Comprehensive outputs for integration
- ✅ Detailed README documentation
- ✅ Security Hub compliance where applicable
- ✅ Cost transparency

## Related Security Modules

- **CloudTrail** (`../security/cloud_trail/`) - Audit all IAM API calls
- **Security Hub** (`../security/security_hub/`) - Centralized security findings
- **GuardDuty** (`../security/guard_duty/`) - Threat detection for IAM anomalies
- **AWS Config** (`../security/aws_config/`) - IAM configuration compliance

