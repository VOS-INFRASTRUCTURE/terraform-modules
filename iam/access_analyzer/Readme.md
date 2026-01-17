# IAM Access Analyzer Module

## Overview

IAM Access Analyzer is an AWS service that helps you identify resources in your organization and accounts that are shared with external entities. It uses automated reasoning to analyze resource-based policies and generates comprehensive findings about external access to your resources.

## What is IAM Access Analyzer?

IAM Access Analyzer continuously monitors your AWS environment and analyzes resource-based policies to identify:
- **S3 buckets** shared with external AWS accounts or made public
- **IAM roles** that can be assumed by external entities
- **KMS keys** that external accounts can use
- **Lambda functions** with external access
- **SQS queues** accessible from outside your account
- **Secrets Manager secrets** shared externally
- **SNS topics** with cross-account subscriptions

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│  Your AWS Account                                            │
│                                                              │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐           │
│  │ S3 Bucket  │  │ IAM Role   │  │ KMS Key    │           │
│  │ (Public)   │  │ (External) │  │ (Shared)   │           │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘           │
│        │               │               │                    │
│        └───────────────┴───────────────┘                    │
│                        │                                     │
│                        ▼                                     │
│            ┌────────────────────────┐                       │
│            │  IAM Access Analyzer   │                       │
│            │  (Continuous Scanner)  │                       │
│            └───────────┬────────────┘                       │
│                        │                                     │
│                        ▼                                     │
│            ┌────────────────────────┐                       │
│            │  Findings Generated    │                       │
│            │  - S3: Public access   │                       │
│            │  - Role: External      │                       │
│            │  - KMS: Account 12345  │                       │
│            └────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │  Security Hub          │
            │  (Aggregated Alerts)   │
            └────────────────────────┘
```

## IAM Access Analyzer vs AWS Config

### Key Differences

| Feature | IAM Access Analyzer | AWS Config |
|---------|-------------------|------------|
| **Primary Purpose** | Identify external access to resources | Track configuration changes and compliance |
| **Focus** | Security - "Who can access my resources from outside?" | Compliance - "Are my resources configured correctly?" |
| **Analysis Method** | Automated reasoning & logic-based analysis | Rule-based evaluation |
| **Findings** | External access permissions | Configuration compliance violations |
| **Scope** | Resource-based policies (IAM, S3, KMS, etc.) | All AWS resource configurations |
| **Use Case** | Prevent data leaks, unauthorized access | Audit trails, compliance monitoring |
| **Real-time** | Near real-time (within minutes) | Near real-time with change triggers |
| **Cost** | Free (with some exceptions) | $0.003 per configuration item recorded |

### When to Use Each

#### Use IAM Access Analyzer When:
✅ You need to identify resources shared with external AWS accounts  
✅ You want to detect publicly accessible resources  
✅ You need to audit cross-account access  
✅ You're concerned about data exfiltration risks  
✅ You need to comply with least-privilege access policies  

**Example Scenarios:**
- "Show me all S3 buckets accessible by external accounts"
- "Which IAM roles can be assumed from outside our organization?"
- "Are any of our KMS keys shared with third parties?"
- "What resources are publicly accessible?"

#### Use AWS Config When:
✅ You need continuous compliance monitoring  
✅ You want to track configuration changes over time  
✅ You need detailed configuration history  
✅ You want to enforce specific security configurations  
✅ You need to answer "Who changed what and when?"  

**Example Scenarios:**
- "Show me all S3 buckets without encryption enabled"
- "Track all changes to security group rules"
- "Alert me when CloudTrail is disabled"
- "Are all EBS volumes encrypted?"
- "Show configuration history for the past 90 days"

### Complementary Use

**Best Practice:** Use BOTH services together!

```
┌─────────────────────────────────────────────────────────────┐
│  Complete Security Posture                                   │
│                                                              │
│  ┌──────────────────────┐    ┌──────────────────────┐      │
│  │  IAM Access Analyzer │    │     AWS Config       │      │
│  │                      │    │                      │      │
│  │  • External access   │    │  • Config compliance │      │
│  │  • Cross-account     │    │  • Change tracking   │      │
│  │  • Public exposure   │    │  • History audit     │      │
│  │  • Policy analysis   │    │  • Rule violations   │      │
│  └──────────┬───────────┘    └──────────┬───────────┘      │
│             │                           │                   │
│             └───────────┬───────────────┘                   │
│                         │                                    │
│                         ▼                                    │
│             ┌────────────────────────┐                      │
│             │    Security Hub        │                      │
│             │  (Unified Dashboard)   │                      │
│             └────────────────────────┘                      │
└─────────────────────────────────────────────────────────────┘
```

**Example:**
- **AWS Config** detects: "S3 bucket encryption is disabled" (configuration issue)
- **IAM Access Analyzer** detects: "S3 bucket is publicly accessible" (access issue)
- **Together:** You know the bucket is both unencrypted AND publicly exposed = CRITICAL!

## How IAM Access Analyzer Relates to Security Hub

```
Security Hub Control: IAM.21
┌─────────────────────────────────────────────────────────────┐
│  AWS Security Hub                                            │
│  Control: IAM.21 - "IAM Access Analyzer should be enabled"  │
│  Status: FAILED ❌                                           │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ Detects missing analyzer
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  IAM Access Analyzer (Not Enabled)                          │
│  - No analyzer created in account                           │
│  - External access risks unmonitored                        │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ Terraform fix
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  aws_accessanalyzer_analyzer resource                       │
│  - Creates analyzer for the account                         │
│  - Enables continuous monitoring                            │
│  - Security Hub IAM.21 → PASSED ✅                          │
└─────────────────────────────────────────────────────────────┘
```

## Real-World Examples

### Scenario 1: S3 Data Leak Prevention

**Problem:**
A developer accidentally set an S3 bucket policy allowing public read access to customer data.

**Without Access Analyzer:**
- Data leak goes unnoticed for months
- Discovered only after data breach
- Regulatory fines and reputation damage

**With Access Analyzer:**
- Finding generated within minutes: "S3 bucket customer-data allows public access"
- Security team receives alert via Security Hub
- Bucket policy fixed immediately
- Zero data exposure

### Scenario 2: Cross-Account Role Audit

**Problem:**
Need to audit all IAM roles that can be assumed by external AWS accounts (partners, vendors).

**Without Access Analyzer:**
- Manual review of hundreds of IAM role trust policies
- Time-consuming and error-prone
- Difficult to maintain

**With Access Analyzer:**
- Automatic detection of all externally assumable roles
- Clear findings: "IAM role vendor-access can be assumed by account 123456789012"
- Easy review and remediation
- Continuous monitoring

### Scenario 3: Compliance Requirement

**Requirement:**
"No resources should be accessible from outside our AWS Organization"

**Solution:**
1. Enable IAM Access Analyzer with Organization scope
2. Set up automated alerts for any external access findings
3. Block deployments if Access Analyzer detects external access
4. Continuous compliance proof for auditors

## Security & Compliance

- **Security Hub Control**: IAM.21
- **Severity**: MEDIUM
- **Compliance Frameworks**:
  - AWS Foundational Security Best Practices
  - CIS AWS Foundations Benchmark
  - NIST CSF
  - PCI DSS
  - SOC 2
  - GDPR (data access auditing)

## What Resources Does Access Analyzer Monitor?

| Resource Type | What It Checks |
|--------------|----------------|
| **S3 Buckets** | Bucket policies, ACLs, public access settings |
| **IAM Roles** | Trust policies allowing external assumption |
| **KMS Keys** | Key policies granting external access |
| **Lambda Functions** | Resource-based policies with external principals |
| **SQS Queues** | Queue policies allowing cross-account access |
| **SNS Topics** | Topic policies with external subscriptions |
| **Secrets Manager** | Secrets shared with external accounts |
| **RDS Snapshots** | Snapshots shared publicly or cross-account |
| **EBS Snapshots** | Snapshots with external access |
| **ECR Repositories** | Repository policies with external pull access |
| **EFS File Systems** | File system policies with external NFS access |

## Types of Findings

### 1. External Access
Resource accessible by entities outside your account/organization.

**Example:** S3 bucket readable by AWS account 123456789012

### 2. Public Access
Resource accessible by anyone on the internet.

**Example:** S3 bucket with public read access

### 3. Cross-Organization Access
Resource shared with accounts outside your AWS Organization.

**Example:** KMS key usable by an AWS account not in your org

## Cost

**FREE** for most use cases:
- ✅ Account-level analyzer: **$0**
- ✅ Findings generation: **$0**
- ✅ API calls: **$0**

**Paid features** (optional):
- ❌ Archive rules for external access findings: **$0**
- ❌ Policy validation: **$0.01 per API call** (if using ValidatePolicy API)
- ❌ Unused access findings: **Additional cost** (per IAM role/user analyzed)

**Typical monthly cost for standard setup: $0**

## Module Usage

```hcl
module "access_analyzer" {
  source = "../../iam/access_analyzer"

  env        = "production"
  project_id = "cerpac"

  # Enable IAM Access Analyzer
  enable_access_analyzer = true

  # Analyzer scope: ACCOUNT or ORGANIZATION
  # ACCOUNT: Analyzes only this AWS account
  # ORGANIZATION: Analyzes entire AWS Organization (requires org management account)
  analyzer_type = "ACCOUNT"

  tags = {
    Compliance = "Required"
    Team       = "Security"
  }
}
```

## Summary

| Aspect | IAM Access Analyzer | AWS Config |
|--------|-------------------|------------|
| **What it answers** | "Who can access my resources?" | "Are my resources configured correctly?" |
| **Security focus** | External access & permissions | Configuration compliance |
| **Analysis type** | Automated reasoning | Rule-based checking |
| **Primary use** | Prevent unauthorized access | Track changes & enforce policies |
| **Cost** | Free | ~$0.003 per resource |
| **Best practice** | Enable together with AWS Config for complete security coverage |

**Key Takeaway:**  
IAM Access Analyzer = **"Access Control Security"**  
AWS Config = **"Configuration Compliance"**  

Use both for comprehensive AWS security! 🔒

