# AWS Systems Manager Security Module

## Overview

This module configures AWS Systems Manager (SSM) security settings, specifically blocking public sharing of SSM documents to meet Security Hub compliance requirements.

## What is SSM Document Public Sharing?

AWS Systems Manager (SSM) allows you to create "documents" - JSON/YAML files that define automated tasks like:
- Running scripts on EC2 instances
- Applying configuration changes
- Automating maintenance tasks
- Running commands across multiple servers

By default, AWS allows you to share these documents publicly (similar to making a GitHub repo public). This is useful for sharing automation scripts with the community, BUT it's a security risk if enabled by accident.

## How This Relates to Security Hub

```
┌─────────────────────────────────────────────────────────────┐
│  AWS Security Hub (Compliance Scanner)                       │
│  - Runs security checks against your account                │
│  - Found: SSM.7 control FAILING                             │
│  - Reason: Public sharing is allowed (not blocked)          │
└─────────────────────────────────────────────────────────────┘
│
│ Detects violation
▼
┌─────────────────────────────────────────────────────────────┐
│  SSM Account Setting (The Actual Problem)                    │
│  - Public sharing: ENABLED (default)  ❌                     │
│  - Anyone can potentially share your SSM docs publicly      │
└─────────────────────────────────────────────────────────────┘
│
│ Our Terraform fix
▼
┌─────────────────────────────────────────────────────────────┐
│  aws_ssm_service_setting resource                            │
│  - Changes setting to: "Disable"  ✅                         │
│  - Blocks public sharing at account level                   │
└─────────────────────────────────────────────────────────────┘
```

## The Flow

1. Security Hub continuously scans your AWS account for security misconfigurations
2. It checks hundreds of controls from standards like:
   - AWS Foundational Security Best Practices
   - CIS AWS Foundations Benchmark
   - PCI DSS, etc.
3. One of these checks is **SSM.7**: "SSM documents should have the block public sharing setting enabled"
4. Security Hub found this setting was not enabled in your account
5. It generated a **CRITICAL** finding and displayed it in your Security Hub console
6. Our Terraform code fixes this by setting the SSM account-level configuration to block public sharing

## Why This Matters

### Without this fix:
- A developer/admin could accidentally share an SSM document publicly
- That document might contain:
  - Internal server configurations
  - IP addresses
  - Database connection patterns
  - Automation workflows attackers could study

### With this fix:
- SSM documents in your account cannot be shared publicly
- Even if someone tries to share one, AWS will block it
- Security Hub SSM.7 control will change from FAIL → PASS

## Usage

### Basic Usage

```hcl
module "ssm_security" {
  source = "../../security/system_manager"

  env        = "production"
  project_id = "myapp"

  # Enable SSM public sharing block (recommended)
  enable_ssm_public_sharing_block = true
}
```

### Advanced Usage

```hcl
module "ssm_security" {
  source = "../../security/system_manager"

  env        = "staging"
  project_id = "cerpac"

  # Optionally disable if needed (not recommended)
  enable_ssm_public_sharing_block = false

  tags = {
    Team       = "Security"
    Compliance = "Required"
  }
}
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `env` | Environment name (e.g., staging, production) | `string` | n/a | yes |
| `project_id` | Project identifier for resource naming and tagging | `string` | n/a | yes |
| `enable_ssm_public_sharing_block` | Whether to block SSM document public sharing (Security Hub SSM.7) | `bool` | `true` | no |
| `tags` | Additional tags to apply to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `ssm_security` | SSM security settings and status including setting_id, setting_value, status, and arn |

### Output Structure

```hcl
{
  enabled       = true                 # Whether the block is enabled
  setting_id    = "arn:aws:ssm:..."   # SSM service setting ARN
  setting_value = "Disable"            # Setting value (Disable = public sharing blocked)
  status        = "Customized"         # Status of the setting
  arn           = "arn:aws:ssm:..."   # Resource ARN
}
```

## Security & Compliance

- **Security Hub Control**: SSM.7
- **Severity**: CRITICAL
- **Compliance Frameworks**:
  - AWS Foundational Security Best Practices v1.0.0
  - CIS AWS Foundations Benchmark
  - NIST CSF
  - ISO 27001

## Cost

**$0** - This is a free security configuration with no additional charges.

## Summary

- **SSM Document Public Sharing Block** = A security hardening setting in AWS Systems Manager
- **Security Hub SSM.7** = A compliance check that verifies this setting is enabled
- **This Terraform module** = The remediation that fixes the finding and makes it reusable across environments

