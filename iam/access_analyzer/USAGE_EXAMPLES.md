# IAM Access Analyzer - Usage Examples

## Example 1: Basic Account-Level Analyzer (Production)

```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "cerpac"
  enable_access_analyzer = true
  analyzer_type          = "ACCOUNT"  # Analyze only this AWS account

  tags = {
    Compliance = "Required"
    Team       = "Security"
  }
}
```

**Use Case:** Single AWS account setup where you want to detect external access to resources.

---

## Example 2: Organization-Level Analyzer (Management Account)

```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "company"
  enable_access_analyzer = true
  analyzer_type          = "ORGANIZATION"  # Analyze entire AWS Organization

  tags = {
    Compliance = "Required"
    Team       = "Security"
    Scope      = "Organization-Wide"
  }
}
```

**Use Case:** AWS Organization with multiple accounts - deploy in management account for centralized visibility.

**Requirements:**
- Must be deployed in AWS Organization management account
- Provides findings for all member accounts
- More comprehensive than account-level analyzers

---

## Example 3: Optional Access Analyzer (Disabled)

```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "development"
  project_id             = "sandbox"
  enable_access_analyzer = false  # Disabled for dev environment

  tags = {
    Environment = "Development"
  }
}
```

**Use Case:** Development/test environments where Access Analyzer is not required.

---

## Example 4: Multi-Environment Setup

**staging.tf:**
```hcl
module "access_analyzer_staging" {
  source = "../../iam/access_analyzer"

  env                    = "staging"
  project_id             = "myapp"
  enable_access_analyzer = true
  analyzer_type          = "ACCOUNT"
}
```

**production.tf:**
```hcl
module "access_analyzer_production" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "myapp"
  enable_access_analyzer = true
  analyzer_type          = "ACCOUNT"
}
```

**Use Case:** Separate Access Analyzer per environment for isolated monitoring.

---

## Example 5: Integration with Security Hub

```hcl
# Enable Security Hub first
module "security_hub" {
  source = "../../security/security_hub"

  env                      = "production"
  project_id               = "cerpac"
  enable_security_hub      = true
  enable_aws_foundational  = true  # Includes IAM.21 control
}

# Enable Access Analyzer (fixes IAM.21 control)
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "cerpac"
  enable_access_analyzer = true
  analyzer_type          = "ACCOUNT"

  depends_on = [module.security_hub]
}
```

**Use Case:** Full security setup with Security Hub monitoring IAM.21 compliance.

**Result:** Security Hub IAM.21 control will show `PASSED` after analyzer is created.

---

## Accessing Outputs

```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env                    = "production"
  project_id             = "cerpac"
  enable_access_analyzer = true
}

# Reference outputs
output "analyzer_info" {
  value = module.access_analyzer.access_analyzer
}
```

**Output structure:**
```json
{
  "enabled": true,
  "analyzer_name": "production-cerpac-access-analyzer",
  "analyzer_arn": "arn:aws:access-analyzer:eu-west-2:123456789012:analyzer/production-cerpac-access-analyzer",
  "analyzer_type": "ACCOUNT",
  "analyzer_id": "production-cerpac-access-analyzer"
}
```

---

## Viewing Findings in AWS Console

After deployment:

1. **Navigate to IAM Access Analyzer:**
   - AWS Console → IAM → Access Analyzer
   - Select your analyzer: `{env}-{project_id}-access-analyzer`

2. **View Findings:**
   - Active findings show resources with external access
   - Resolved findings show archived/remediated issues

3. **Review a Finding:**
   ```
   Finding: S3 bucket "my-bucket" is publicly accessible
   Resource: arn:aws:s3:::my-bucket
   Principal: *
   Access: s3:GetObject
   Recommendation: Update bucket policy to restrict access
   ```

4. **Archive Finding (if intended):**
   - Click finding → Archive
   - Add justification: "Public access required for static website hosting"

---

## Common Finding Examples

### Finding 1: Public S3 Bucket
```
Resource: arn:aws:s3:::company-public-data
Finding: S3 bucket allows public read access
Principal: *
Action: s3:GetObject
Status: ACTIVE
```

**Remediation:** Update bucket policy or mark as archived if intentional.

---

### Finding 2: Cross-Account IAM Role
```
Resource: arn:aws:iam::123456789012:role/vendor-access
Finding: IAM role can be assumed by external account
Principal: arn:aws:iam::999999999999:root
Action: sts:AssumeRole
Status: ACTIVE
```

**Remediation:** Review trust policy; add external ID condition for security.

---

### Finding 3: Shared KMS Key
```
Resource: arn:aws:kms:eu-west-2:123456789012:key/abc123
Finding: KMS key grants decrypt permissions to external account
Principal: arn:aws:iam::888888888888:root
Action: kms:Decrypt
Status: ACTIVE
```

**Remediation:** Review key policy; remove external account if unnecessary.

---

## Cost Analysis

**IAM Access Analyzer costs:**
- ✅ Account-level analyzer: **$0/month**
- ✅ Organization-level analyzer: **$0/month**
- ✅ Findings generation: **$0**
- ❌ Unused access findings (optional): **Additional cost**

**Example monthly cost:**
```
IAM Access Analyzer (account-level):  $0.00
Total:                                 $0.00
```

---

## Compliance Mapping

| Framework | Control | Requirement |
|-----------|---------|-------------|
| **Security Hub** | IAM.21 | IAM Access Analyzer should be enabled |
| **CIS AWS** | 1.20 | Ensure IAM Access analyzer is enabled |
| **PCI DSS** | 7.1 | Limit access to system components |
| **SOC 2** | CC6.1 | Logical access controls |
| **GDPR** | Art. 32 | Security of processing (access monitoring) |
| **NIST CSF** | PR.AC-4 | Access permissions managed |

---

## Troubleshooting

### Issue 1: Analyzer Not Created
**Symptom:** `terraform apply` completes but analyzer not visible in console

**Solution:**
```hcl
# Verify variable is set
enable_access_analyzer = true  # Must be true
```

### Issue 2: Organization Analyzer Fails
**Error:** `AccessDeniedException: You must be in the organization management account`

**Solution:** Deploy organization-level analyzer only from AWS Organization management account, or use `ACCOUNT` type instead.

### Issue 3: Too Many Findings
**Symptom:** Hundreds of findings for legitimate external access

**Solution:**
1. Review each finding
2. Archive legitimate external access with justification
3. Create archive rules for expected patterns
4. Fix actual security issues

---

## Next Steps

After deploying Access Analyzer:

1. ✅ Review initial findings (expect 10-50 findings)
2. ✅ Archive legitimate external access (with justification)
3. ✅ Remediate security issues (public S3 buckets, etc.)
4. ✅ Set up Security Hub alerts for new findings
5. ✅ Schedule weekly finding reviews
6. ✅ Document approved external access in runbook

