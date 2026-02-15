# AWS WAF (Web Application Firewall) Terraform Module

Terraform module to protect web applications from common exploits using AWS WAFv2 with managed rule groups, custom rules, and intelligent log routing.

## Overview

AWS WAF helps protect your web applications from common web exploits and bots that could affect availability, compromise security, or consume excessive resources.

- **OWASP Protection**: Core Rule Set covering OWASP Top 10 vulnerabilities
- **SQL Injection Protection**: Specialized rules for SQL injection attacks
- **Known Bad Inputs**: Protection against known malicious patterns and CVEs
- **Rate Limiting**: DDoS protection with configurable thresholds
- **IP Reputation**: Block requests from known malicious IPs
- **Intelligent Logging**: Route logs by action (blocked/allowed) with different retention
- **Cost Optimized**: Modular rules with WCU tracking and optional paid features

## Module Structure

```
waf/
├── main.tf                      # Module entry point with overview
├── variables.tf                 # Comprehensive configuration variables
├── outputs.tf                   # Consolidated output object
├── waf.tf                       # Web ACL with managed rule groups
├── bucket.tf                    # S3 bucket for WAF logs
├── waf_logging.tf               # WAF logging configuration
├── waf_firehose.tf              # Kinesis Firehose delivery stream
├── waf_firehose_iam.tf          # IAM roles for Firehose
├── waf_log_router_lambda.tf     # Lambda for intelligent log routing
├── lambda/
│   ├── waf_log_router.py        # Lambda function code
│   └── waf_log_router.zip       # Packaged Lambda
└── README.md                    # This file
```

## Features

✅ **Phase 1: Baseline Protection** (enabled by default)
- Core Rule Set (OWASP Top 10) - 700 WCU
- Known Bad Inputs (CVEs, malicious patterns) - 200 WCU
- SQL Injection Protection - 200 WCU
- IP Reputation List (malicious IPs) - 25 WCU
- Rate Limiting (DDoS protection) - 0 WCU

✅ **Phase 2: Stack-Specific Protection** (optional)
- WordPress, PHP, Linux, Unix, Windows rule sets
- Enable based on your application stack

✅ **Phase 3: Advanced Protection** (paid, optional)
- Bot Control ($10/month + usage)
- Account Takeover Prevention ($10/month + usage)
- Account Creation Fraud Prevention ($10/month + usage)

✅ **Intelligent Logging**
- Kinesis Firehose delivery to S3
- Lambda-based log routing (blocked/allowed/errors)
- Cost-optimized retention (90 days blocked, 7 days allowed)
- GZIP compression

## Prerequisites

- Application Load Balancer (ALB) or CloudFront distribution
- (Optional) Kinesis Firehose for logging
- (Optional) Lambda function for log routing

## Usage

### Basic Configuration (Baseline Protection)

```terraform
module "waf" {
  source = "../../modules/security/waf"

  env        = "production"
  project_id = "cerpac"

  # ALB Association
  alb_arn  = aws_lb.main.arn
  alb_name = "production-alb"

  # Phase 1: Baseline Protection (recommended)
  enable_core_rule_set        = true   # OWASP Top 10
  enable_known_bad_inputs     = true   # Known malicious patterns
  enable_sqli_rule_set        = true   # SQL injection
  enable_ip_reputation_list   = true   # Malicious IPs

  # File Upload Support - Exclude SizeRestrictions_BODY rule
  # Set to true if your app supports file uploads (profile pics, documents, etc.)
  exclude_size_restrictions_body = false  # Default: false (blocks large bodies)

  # Rate Limiting
  enable_rate_limiting = true
  rate_limit_threshold = 2000  # 2000 requests per IP per 5 minutes

  # Logging (optional but recommended)
  enable_waf_logging          = true
  blocked_logs_retention_days = 90
  allowed_logs_retention_days = 7

  tags = {
    ManagedBy  = "Terraform"
    CostCenter = "Security"
  }
}
```

### Advanced Configuration (with Stack-Specific Rules)

```terraform
module "waf" {
  source = "../../modules/security/waf"

  env        = "production"
  project_id = "cerpac"

  # ALB Association
  alb_arn  = aws_lb.main.arn
  alb_name = "production-alb"

  # Phase 1: Baseline Protection
  enable_core_rule_set        = true
  enable_known_bad_inputs     = true
  enable_sqli_rule_set        = true
  enable_ip_reputation_list   = true
  enable_admin_protection     = true   # Admin page protection
  enable_anonymous_ip_list    = false  # Blocks VPNs (may affect users)

  # Path Exclusions - Exclude from Core/Admin/SQLi/KnownBadInputs rules
  # Uses scope_down_statement (no WCU cost)
  # Other rules (rate limiting, IP reputation) still apply
  core_rule_sets_excluded_paths = [
    "/log-viewer",        # Internal log viewer (query params look like SQL)
    "/admin/debug",       # Debug panel (secured by auth + IP restriction)
    "/internal/metrics",  # Monitoring endpoint
  ]

  # Rate Limiting
  enable_rate_limiting = true
  rate_limit_threshold = 5000  # Higher threshold for high-traffic sites

  # Phase 2: Stack-Specific (enable based on your stack)
  enable_php_rules    = true   # Only if using PHP
  enable_linux_rules  = true   # Only if Linux backend
  enable_wordpress_rules = false  # Only if WordPress

  # Phase 3: Paid Features (additional cost)
  enable_bot_control = false  # $10/month + usage
  enable_atp         = false  # $10/month + usage

  # Logging with custom retention
  enable_waf_logging          = true
  blocked_logs_retention_days = 365  # Keep blocked requests 1 year
  allowed_logs_retention_days = 7
  force_destroy_log_bucket    = false

  # Firehose Configuration
  firehose_buffering_size     = 64
  firehose_buffering_interval = 60
  enable_firehose_compression = true

  tags = {
    ManagedBy  = "Terraform"
    CostCenter = "Security"
    Compliance = "PCI-DSS"
  }
}
```

### Full Protection (with Paid Features)

```terraform
module "waf" {
  source = "../../modules/security/waf"

  env        = "production"
  project_id = "cerpac"

  # ALB Association
  alb_arn  = aws_lb.main.arn
  alb_name = "production-alb"

  # Phase 1: All baseline rules
  enable_core_rule_set        = true
  enable_known_bad_inputs     = true
  enable_sqli_rule_set        = true
  enable_ip_reputation_list   = true
  enable_admin_protection     = true
  enable_anonymous_ip_list    = true

  # Rate Limiting
  enable_rate_limiting = true
  rate_limit_threshold = 2000

  # Phase 2: Stack-specific
  enable_php_rules   = true
  enable_linux_rules = true

  # Phase 3: Paid Features (HIGH SECURITY)
  enable_bot_control = true
  bot_control_inspection_level = "TARGETED"  # More aggressive

  enable_atp = true
  atp_login_path      = "/api/auth/login"
  atp_username_field  = "/email"
  atp_password_field  = "/password"

  enable_acfp = true
  acfp_creation_path          = "/api/auth/signup"
  acfp_registration_page_path = "/register"
  acfp_username_field         = "/username"
  acfp_email_field            = "/email"

  # Logging
  enable_waf_logging          = true
  blocked_logs_retention_days = 365
  allowed_logs_retention_days = 30

  tags = {
    ManagedBy   = "Terraform"
    CostCenter  = "Security"
    Compliance  = "SOC2-PCI-HIPAA"
    Environment = "production"
  }
}
```

### Minimal Configuration (WAF Only, No Logging)

```terraform
module "waf" {
  source = "../../modules/security/waf"

  env        = "production"
  project_id = "cerpac"

  # ALB Association
  alb_arn = aws_lb.main.arn

  # Minimal baseline protection
  enable_core_rule_set      = true
  enable_known_bad_inputs   = true
  enable_sqli_rule_set      = true
  enable_ip_reputation_list = true
  enable_rate_limiting      = true

  # Disable logging to save costs
  enable_waf_logging = false

  # Disable optional rules
  enable_admin_protection  = false
  enable_anonymous_ip_list = false
  enable_wordpress_rules   = false
  enable_php_rules         = false
  enable_linux_rules       = false

  # Disable paid features
  enable_bot_control = false
  enable_atp         = false
  enable_acfp        = false
}
```

## Outputs

This module provides a single comprehensive `waf` output object:

```terraform
output "waf" {
  value = {
    # Web ACL details
    web_acl = {
      id          = "abc123..."
      arn         = "arn:aws:wafv2:..."
      name        = "production-cerpac-waf"
      capacity    = 1325  # Current WCU usage
      scope       = "REGIONAL"
      description = "Production WAF"
    }

    # ALB Association
    association = {
      resource_arn = "arn:aws:elasticloadbalancing:..."
      web_acl_arn  = "arn:aws:wafv2:..."
    }

    # Logging configuration
    logging = {
      bucket_name         = "production-cerpac-app-alb-waf-logs"
      bucket_arn          = "arn:aws:s3:::..."
      firehose_stream_arn = "arn:aws:firehose:..."
      
      retention = {
        blocked_days = 90
        allowed_days = 7
        error_days   = 7
      }
      
      lambda_router = {
        function_name = "production-cerpac-waf-log-router"
        function_arn  = "arn:aws:lambda:..."
      }
    }

    # Rule groups status
    rule_groups = {
      core_rule_set     = true
      known_bad_inputs  = true
      sqli_protection   = true
      ip_reputation     = true
      # ... all rule groups
    }

    # Rate limiting
    rate_limiting = {
      enabled   = true
      threshold = 2000
    }

    # Summary with WCU tracking
    summary = {
      total_wcu_used         = 1325
      wcu_remaining          = 175
      baseline_rules_enabled = 4
      stack_rules_enabled    = 2
      paid_features_enabled  = 1
    }
  }
}
```

### Using Outputs

```terraform
module "waf" {
  source = "../../modules/security/waf"
  # ...configuration...
}

# Get Web ACL ID for AWS CLI commands
output "waf_web_acl_id" {
  value = module.waf.waf.web_acl.id
}

# Check WCU usage
output "waf_capacity" {
  value = {
    used      = module.waf.waf.summary.total_wcu_used
    remaining = module.waf.waf.summary.wcu_remaining
  }
}

# Get log bucket for analysis
output "waf_log_bucket" {
  value = module.waf.waf.logging.bucket_name
}

# Use in CloudWatch dashboard
resource "aws_cloudwatch_dashboard" "waf" {
  dashboard_name = "waf-monitoring"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", { stat = "Sum" }],
            [".", "AllowedRequests", { stat = "Sum" }]
          ]
          period = 300
          region = "eu-west-2"
          title  = "WAF Requests"
        }
      }
    ]
  })
}
```

## WCU (Web ACL Capacity Units) Management

AWS WAF has a hard limit of **1500 WCU per Web ACL**. Each rule group consumes WCU:

### Rule Group WCU Costs

| Rule Group | WCU Cost | Enabled by Default |
|------------|----------|-------------------|
| **Phase 1: Baseline** | | |
| Core Rule Set (OWASP) | 700 | ✅ Yes |
| Known Bad Inputs | 200 | ✅ Yes |
| SQL Injection | 200 | ✅ Yes |
| IP Reputation List | 25 | ✅ Yes |
| Admin Protection | 100 | ❌ No |
| Anonymous IP List | 50 | ❌ No |
| **Rate Limiting** | **0** | **✅ Yes** |
| **Baseline Subtotal** | **1125** | |
| **Phase 2: Stack-Specific** | | |
| WordPress Rules | 100 | ❌ No |
| PHP Rules | 100 | ❌ No |
| Linux Rules | 200 | ❌ No |
| Unix/POSIX Rules | 100 | ❌ No |
| Windows Rules | 200 | ❌ No |
| **Phase 3: Paid** | | |
| Bot Control | 50 | ❌ No |
| ATP (Account Takeover) | 50 | ❌ No |
| ACFP (Fraud Prevention) | 50 | ❌ No |

### WCU Calculator

The module automatically calculates WCU usage in outputs:

```terraform
output "waf_wcu" {
  value = {
    used      = module.waf.waf.summary.total_wcu_used      # e.g., 1325
    remaining = module.waf.waf.summary.wcu_remaining       # e.g., 175
    limit     = 1500
  }
}
```

**Warning**: Enabling all rules will exceed the 1500 WCU limit. Choose rules based on your application needs.

## Cost Estimate

### Typical Production Environment (Baseline Protection)

| Component | Volume | Unit Cost | Monthly Cost |
|-----------|--------|-----------|--------------|
| **WAF Base** | 1 Web ACL | $5/month | $5.00 |
| **WAF Requests** | 10M requests | $0.60 per 1M | $6.00 |
| **WAF Rules** | 5 rules | Free (AWS managed) | $0.00 |
| **S3 Storage (logs)** | 50 GB | $0.023/GB | $1.15 |
| **Kinesis Firehose** | 50 GB | $0.029/GB | $1.45 |
| **Lambda Invocations** | 10M | $0.20 per 1M | $2.00 |
| **CloudWatch Logs** | 5 GB | $0.50/GB | $2.50 |
| **TOTAL** | | | **~$18.10/month** |

### With Paid Features (Bot Control + ATP)

| Additional Component | Cost |
|---------------------|------|
| Bot Control | $10/month + $1 per 1M requests |
| ATP (Account Takeover) | $10/month + $1 per 1k login attempts |
| ACFP (Fraud Prevention) | $10/month + $1 per 1k signups |
| **Estimated Total** | **~$50-80/month** |

### Cost Optimization Tips

1. **Disable Unused Stack-Specific Rules**
   ```terraform
   enable_wordpress_rules = false  # If not using WordPress
   enable_windows_rules   = false  # If not using Windows
   ```

2. **Reduce Log Retention**
   ```terraform
   allowed_logs_retention_days = 1  # Instead of 7 days
   ```

3. **Disable Logging in Dev/Test**
   ```terraform
   enable_waf_logging = false  # Saves ~$5/month
   ```

4. **Use Lower Rate Limit Threshold**
   ```terraform
   rate_limit_threshold = 500  # More aggressive blocking
   ```

5. **Skip Paid Features Unless Needed**
   ```terraform
   enable_bot_control = false  # Saves $10-20/month
   enable_atp         = false  # Saves $10-20/month
   ```

## AWS Managed Rule Groups Explained

### Phase 1: Baseline Protection (Always Recommended)

#### 1. Core Rule Set (OWASP Top 10) - 700 WCU
**Protects against**: OWASP Top 10 vulnerabilities

Common attacks blocked:
- Cross-site scripting (XSS)
- Local file inclusion (LFI)
- Remote code execution (RCE)
- SQL injection (basic)
- Path traversal

**Recommendation**: Always enable ✅

**File Upload Support**: 
If your application supports file uploads (profile pictures, documents, attachments), you may need to exclude the `SizeRestrictions_BODY` rule:

```terraform
enable_core_rule_set           = true
exclude_size_restrictions_body = true  # Allow file uploads
```

**What this does**:
- Changes `SizeRestrictions_BODY` rule from BLOCK to COUNT (log only)
- Allows large request bodies (needed for multipart/form-data file uploads)
- All other Core Rule Set rules still actively protect your application
- The rule still logs large bodies, but doesn't block them

**When to enable exclusion**:
- ✅ Your app has file upload functionality
- ✅ You're seeing legitimate uploads being blocked
- ✅ You have application-level upload size limits
- ✅ You've configured ALB request body size limits

**Security considerations when excluded**:
- ⚠️ Ensure your application validates and limits upload sizes
- ⚠️ Set maximum file sizes at the application level
- ⚠️ Consider using S3 presigned URLs for large uploads instead
- ⚠️ Monitor CloudWatch logs for excessive large body requests

#### 2. Known Bad Inputs - 200 WCU
**Protects against**: Known malicious patterns and CVEs

Includes protection for:
- Log4Shell (Log4j)
- Spring4Shell
- Text4Shell
- Known exploit patterns

**Recommendation**: Always enable ✅

#### 3. SQL Injection Rule Set - 200 WCU
**Protects against**: Advanced SQL injection attacks

More comprehensive than Core Rule Set's SQLi protection.

**Recommendation**: Always enable ✅

#### 4. IP Reputation List - 25 WCU
**Protects against**: Requests from known malicious IPs

Based on Amazon threat intelligence:
- Botnet IPs
- Known scanners
- Exploitation sources

**Recommendation**: Always enable ✅

#### 5. Admin Protection - 100 WCU
**Protects against**: Admin panel attacks

**Warning**: Can cause false positives on admin pages.

**Recommendation**: Enable if you have admin panels, test first ⚠️

#### 6. Anonymous IP List - 50 WCU
**Protects against**: Requests from VPNs, proxies, Tor

**Warning**: Will block legitimate users behind corporate VPNs.

**Recommendation**: Test in COUNT mode first ⚠️

### Phase 2: Stack-Specific Rules (Conditional)

#### WordPress Rules - 100 WCU
Only enable if using WordPress. Useless (and noisy) otherwise.

#### PHP Rules - 100 WCU
Only enable if using PHP backend.

#### Linux/Unix/Windows Rules - 100-200 WCU each
Only enable based on your OS. Generally unnecessary behind ALB.

### Phase 3: Paid Features

#### Bot Control - 50 WCU ($10/month + usage)
**Protects against**: Automated bots, scrapers, crawlers

Inspection levels:
- `COMMON`: General bot detection
- `TARGETED`: More aggressive (may block good bots)

**Recommendation**: Enable if bot traffic is a concern 💰

#### ATP (Account Takeover Prevention) - 50 WCU ($10/month + usage)
**Protects against**: Credential stuffing, compromised credentials

**Requirements**:
- Must configure login endpoint path
- Must specify username/password field locations

**Recommendation**: Enable if you have login endpoints 💰

#### ACFP (Account Creation Fraud Prevention) - 50 WCU ($10/month + usage)
**Protects against**: Fake account creation, mass registration

**Requirements**:
- Must configure signup endpoint path
- Must specify form field locations

**Recommendation**: Enable if account abuse is a problem 💰

## Logging Architecture

### Log Flow

```
┌─────────────────┐
│   AWS WAF       │
│   Web ACL       │
└────────┬────────┘
         │
         │ Logs
         ▼
┌─────────────────┐
│ Kinesis Firehose│
└────────┬────────┘
         │
         │ Invokes
         ▼
┌─────────────────────┐
│  Lambda Function    │
│  (Log Router)       │
│  - Checks action    │
│  - Routes to prefix │
└────────┬────────────┘
         │
         ├─────> s3://bucket/blocked/    (90 days)
         ├─────> s3://bucket/allowed/    (7 days)
         └─────> s3://bucket/errors/     (7 days)
```

### Log Format

WAF logs are in JSON format:

```json
{
  "timestamp": 1673456789000,
  "formatVersion": 1,
  "webaclId": "arn:aws:wafv2:...",
  "terminatingRuleId": "AWS#AWSManagedRulesCommonRuleSet",
  "terminatingRuleType": "MANAGED_RULE_GROUP",
  "action": "BLOCK",
  "httpRequest": {
    "clientIp": "192.0.2.1",
    "country": "US",
    "uri": "/api/users",
    "httpMethod": "POST"
  },
  "rateBasedRuleList": [],
  "ruleGroupList": []
}
```

### Querying Logs with Athena

**Step 1**: Create Athena table

```sql
CREATE EXTERNAL TABLE waf_logs (
  timestamp bigint,
  formatversion int,
  webaclid string,
  terminatingruleid string,
  terminatingruletype string,
  action string,
  httpsourcename string,
  httpsourceid string,
  rulegrouplist array<struct<
    rulegroupid:string,
    terminatingrule:struct<ruleid:string,action:string>,
    nonterminatingmatchingrules:array<struct<ruleid:string,action:string>>,
    excludedrules:array<struct<ruleid:string>>
  >>,
  ratebasedrulelist array<struct<
    ratelimitid:string,
    limitkey:string,
    maxrateallowed:int
  >>,
  httprequest struct<
    clientip:string,
    country:string,
    headers:array<struct<name:string,value:string>>,
    uri:string,
    args:string,
    httpversion:string,
    httpmethod:string,
    requestid:string
  >
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://production-cerpac-app-alb-waf-logs/blocked/';
```

**Step 2**: Query blocked requests

```sql
-- Find top blocked IPs
SELECT 
  httprequest.clientip,
  COUNT(*) as block_count,
  terminatingruleid
FROM waf_logs
WHERE action = 'BLOCK'
GROUP BY httprequest.clientip, terminatingruleid
ORDER BY block_count DESC
LIMIT 100;

-- Find most common attack types
SELECT 
  terminatingruleid,
  COUNT(*) as count
FROM waf_logs
WHERE action = 'BLOCK'
GROUP BY terminatingruleid
ORDER BY count DESC;

-- Find requests from specific country
SELECT *
FROM waf_logs
WHERE httprequest.country = 'CN'
  AND action = 'BLOCK'
LIMIT 100;
```

## Troubleshooting

### WAF Blocking Legitimate Traffic

**Issue**: False positives blocking valid requests

**Diagnosis**:
```bash
# Check blocked requests in CloudWatch Insights
aws logs start-query \
  --log-group-name /aws/firehose/production-cerpac-waf \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, action, terminatingRuleId, httpRequest.uri
                   | filter action = "BLOCK"
                   | sort @timestamp desc
                   | limit 100'
```

**Solutions**:
1. **Disable specific rules** (not recommended):
   ```terraform
   enable_admin_protection = false
   ```

2. **Use COUNT mode** to test rules without blocking:
   - In AWS Console: WAF → Web ACL → Rules → Edit rule → Override to Count

3. **Add rule exceptions** (advanced):
   - Create custom rule to allow specific patterns
   - Configure scope-down statements

### High WCU Usage

**Issue**: Approaching 1500 WCU limit

**Check current usage**:
```terraform
output "wcu_status" {
  value = module.waf.waf.summary
}
```

**Solutions**:
1. **Disable unused stack-specific rules**:
   ```terraform
   enable_wordpress_rules = false
   enable_php_rules       = false
   enable_windows_rules   = false
   ```

2. **Choose between similar rules**:
   - If using Bot Control, you may not need Anonymous IP List

### WAF Not Blocking Attacks

**Issue**: Known attacks getting through

**Verify WAF is active**:
```bash
# Check Web ACL association
aws wafv2 list-resources-for-web-acl \
  --web-acl-arn <web_acl_arn> \
  --scope REGIONAL
```

**Verify rules are enabled**:
```bash
# Get Web ACL configuration
aws wafv2 get-web-acl \
  --scope REGIONAL \
  --id <web_acl_id> \
  --name production-cerpac-waf
```

**Common Issues**:
1. Rules set to COUNT mode instead of BLOCK
2. Web ACL not associated with ALB
3. Request not matching rule criteria

### No Logs Appearing in S3

**Issue**: WAF logs not being delivered

**Check Firehose status**:
```bash
# Check delivery stream errors
aws logs filter-log-events \
  --log-group-name /aws/firehose/production-cerpac-waf \
  --filter-pattern ERROR
```

**Check Lambda function**:
```bash
# Check Lambda errors
aws logs tail /aws/lambda/production-cerpac-waf-log-router --follow
```

**Common Issues**:
1. IAM role lacks S3 permissions
2. Lambda function failing
3. Logging not enabled on Web ACL

### High Costs

**Issue**: Unexpectedly high WAF costs

**Cost breakdown**:
```bash
# Check request volume
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name AllowedRequests \
  --dimensions Name=Rule,Value=ALL \
  --start-time 2026-01-01T00:00:00Z \
  --end-time 2026-01-11T23:59:59Z \
  --period 86400 \
  --statistics Sum
```

**Solutions**:
1. **Reduce log retention**:
   ```terraform
   allowed_logs_retention_days = 1
   ```

2. **Disable paid features if not needed**:
   ```terraform
   enable_bot_control = false
   enable_atp         = false
   ```

3. **Increase rate limit threshold** (less blocking):
   ```terraform
   rate_limit_threshold = 10000
   ```

## Best Practices

### ✅ Recommended

- [x] Enable baseline protection (Core, SQLi, Known Bad Inputs, IP Reputation)
- [x] Enable rate limiting to prevent DDoS
- [x] Enable logging for security analysis
- [x] Use longer retention for blocked requests (90+ days)
- [x] Use shorter retention for allowed requests (7 days)
- [x] Test new rules in COUNT mode first
- [x] Monitor WAF metrics in CloudWatch
- [x] Review blocked requests weekly
- [x] Calculate WCU before enabling new rules
- [x] Tag all WAF resources properly

### ❌ Avoid

- [ ] Enabling all rules without testing (WCU limit + false positives)
- [ ] Disabling logging (blind to attacks)
- [ ] Using same retention for all log types (cost inefficient)
- [ ] Enabling Anonymous IP List without testing (blocks VPNs)
- [ ] Ignoring CloudWatch metrics
- [ ] Not reviewing blocked requests
- [ ] Enabling paid features without ROI analysis

## Compliance Mapping

| Standard | Requirement | Coverage |
|----------|-------------|----------|
| **PCI-DSS 6.6** | Web application firewall | ✅ Full |
| **OWASP Top 10** | Common vulnerabilities | ✅ Full |
| **CIS AWS Foundations** | Network protection | ✅ Supported |
| **SOC 2 CC6.6** | Logical access controls | ✅ Supported |
| **HIPAA** | Access controls, audit logs | ✅ Supported |
| **GDPR** | Data protection measures | ✅ Supported |
| **ISO 27001 A.13.1** | Network security controls | ✅ Supported |
| **NIST 800-53 SC-7** | Boundary protection | ✅ Supported |

## Variables Reference

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `env` | string | - | Yes | Environment name |
| `project_id` | string | `"cerpac"` | No | Project identifier |
| `tags` | map(string) | `{}` | No | Additional resource tags |
| `enable_waf` | bool | `true` | No | Enable WAF |
| `waf_scope` | string | `"REGIONAL"` | No | REGIONAL or CLOUDFRONT |
| `alb_arn` | string | `null` | No* | ALB ARN (* required if associating) |
| `alb_name` | string | `null` | No | ALB name for naming |
| `enable_core_rule_set` | bool | `true` | No | OWASP Top 10 (700 WCU) |
| `enable_known_bad_inputs` | bool | `true` | No | Known malicious patterns (200 WCU) |
| `enable_sqli_rule_set` | bool | `true` | No | SQL injection (200 WCU) |
| `enable_ip_reputation_list` | bool | `true` | No | Malicious IPs (25 WCU) |
| `enable_admin_protection` | bool | `false` | No | Admin pages (100 WCU) |
| `enable_anonymous_ip_list` | bool | `false` | No | VPN/Proxy blocking (50 WCU) |
| `enable_rate_limiting` | bool | `true` | No | Rate limiting |
| `rate_limit_threshold` | number | `1000` | No | Requests per IP per 5 min |
| `enable_wordpress_rules` | bool | `false` | No | WordPress (100 WCU) |
| `enable_php_rules` | bool | `false` | No | PHP (100 WCU) |
| `enable_linux_rules` | bool | `false` | No | Linux OS (200 WCU) |
| `enable_unix_rules` | bool | `false` | No | Unix/POSIX (100 WCU) |
| `enable_windows_rules` | bool | `false` | No | Windows OS (200 WCU) |
| `enable_bot_control` | bool | `false` | No | Bot Control (50 WCU, PAID) |
| `bot_control_inspection_level` | string | `"COMMON"` | No | COMMON or TARGETED |
| `enable_atp` | bool | `false` | No | Account Takeover Prevention (PAID) |
| `atp_login_path` | string | `"/login"` | No | Login endpoint |
| `enable_acfp` | bool | `false` | No | Account Creation Fraud (PAID) |
| `acfp_creation_path` | string | `"/signup"` | No | Signup endpoint |
| `enable_waf_logging` | bool | `true` | No | Enable logging |
| `blocked_logs_retention_days` | number | `90` | No | Blocked logs retention |
| `allowed_logs_retention_days` | number | `7` | No | Allowed logs retention |
| `error_logs_retention_days` | number | `7` | No | Error logs retention |
| `force_destroy_log_bucket` | bool | `false` | No | Allow bucket deletion |
| `firehose_buffering_size` | number | `64` | No | Buffer size (64-128 MB) |
| `firehose_buffering_interval` | number | `60` | No | Buffer interval (60-900 sec) |
| `enable_firehose_compression` | bool | `true` | No | GZIP compression |

## Related Modules

- **ALB (Application Load Balancer)**: Target for WAF protection
- **CloudFront**: Alternative WAF scope (CLOUDFRONT)
- **Security Hub**: Centralized security findings
- **GuardDuty**: Threat detection (complementary)

## Support

For issues or questions:
- Internal: Contact Security Team
- Documentation: See [AWS WAF Documentation](https://docs.aws.amazon.com/waf/)
- Pricing: [AWS WAF Pricing](https://aws.amazon.com/waf/pricing/)

---

**Last Updated**: January 11, 2026  
**Version**: 1.0.0  
**Maintained By**: Security Team

