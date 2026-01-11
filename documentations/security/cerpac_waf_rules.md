# AWS WAF Rules Configuration for CERPAC Production

This document provides detailed information about the WAF rules protecting the CERPAC Application Load Balancer.

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Currently Active Rules](#currently-active-rules)
3. [Recently Disabled Rules](#recently-disabled-rules)
4. [Available But Disabled Rules](#available-but-disabled-rules)
5. [Protection Coverage](#protection-coverage)
6. [WCU Budget Management](#wcu-budget-management)
7. [How to Enable/Disable Rules](#how-to-enabledisable-rules)
8. [Troubleshooting](#troubleshooting)
9. [Complete Rule Inventory](#complete-rule-inventory)

---

## Overview

**Web ACL**: `production-cerpac-waf`  
**Associated Resource**: CERPAC Application Load Balancer  
**Scope**: Regional (eu-west-2)  
**Default Action**: Allow (block only on rule match)  
**Configuration File**: `production-infrastructure/cerpac_waf.tf`

The WAF uses a **layered defense strategy** with three phases:
- **Phase 1**: Baseline protection (core rules currently active)
- **Phase 2**: Conditional/stack-specific rules (commented out, enable as needed)
- **Phase 3**: Paid advanced protection (commented out, requires additional cost)

---

## ✅ Currently Active Rules (Phase 1 - Free Tier)

These rules are **actively protecting** your CERPAC application:

| Rule Name | Capacity (WCU) | Priority | Protection Against |
|-----------|----------------|----------|-------------------|
| **Core Rule Set** (OWASP Top 10) | 700 | 1 | SQL injection, XSS, RCE, LFI/RFI, SSRF |
| **Known Bad Inputs** | 200 | 3 | Log4j, SpringShell, known CVEs |
| **SQL Injection Protection** | 200 | 4 | Advanced SQLi patterns and bypass techniques |
| **Amazon IP Reputation List** | 25 | 5 | Known malicious IPs, botnets, scanners |
| **Rate Limiting (Per IP)** | 0* | 7 | DDoS, brute force (1000 req/5min/IP) |
| **Total WCU Used** | **1,125 / 1,500** | | 🎯 **375 WCU available** |

*Rate-based rules don't count toward WCU limit

---

## 💤 Recently Disabled Rules

These rules were **disabled** to reduce false positives and free up WCU capacity:

| Rule Name | Capacity (WCU) | Priority | Reason for Disabling | How to Re-enable |
|-----------|----------------|----------|---------------------|------------------|
| **Admin Protection** | 100 | 2 | May block legitimate admin access | Uncomment in `cerpac_waf.tf` lines 73-98 |
| **Anonymous IP List** | 50 | 6 | Blocks corporate VPNs, legitimate proxies | Uncomment in `cerpac_waf.tf` lines 190-221 |

### When to Re-enable These Rules

**Admin Protection**:
- Enable if you see targeted admin panel attacks in logs
- Consider using count mode first to assess impact
- Alternative: Use custom IP whitelist for admin paths

**Anonymous IP List**:
- Enable if you see abuse from VPN/proxy services
- Warning: May impact legitimate users behind corporate VPNs
- Consider testing in count mode first

---

## 📋 Available But Disabled Rules

### Phase 2: Conditional/Stack-Specific (Free Tier)

These are **commented out** and should only be enabled based on your specific application stack:

| Rule Name | Capacity (WCU) | Priority | When to Enable | Lines in File |
|-----------|----------------|----------|----------------|---------------|
| **WordPress Application** | 100 | 10 | If using WordPress CMS | 280-301 |
| **PHP Application** | 100 | 11 | If using PHP backend | 303-324 |
| **Linux OS Protection** | 200 | 12 | If OS commands are exposed | 326-347 |
| **POSIX OS Protection** | 100 | 13 | If using POSIX systems | 349-370 |
| **Windows OS Protection** | 200 | 14 | If using Windows servers | 372-393 |

⚠️ **WARNING**: You currently have **375 WCU available**. Choose selectively to avoid exceeding the 1,500 WCU limit!

---

### Phase 3: Paid Tier (Additional Cost)

These require **additional AWS charges** beyond standard WAF pricing:

| Rule Name | Capacity (WCU) | Priority | Cost | When to Enable | Lines in File |
|-----------|----------------|----------|------|----------------|---------------|
| **Bot Control** | 50 | 20 | $10/month + $1/million requests | Automated bot traffic concerns | 407-444 |
| **Account Takeover Prevention (ATP)** | 50 | 21 | $10/month + $1/1,000 login attempts | Credential stuffing attacks | 446-498 |
| **Account Creation Fraud Prevention (ACFP)** | 50 | 22 | $10/month + $1/1,000 signup attempts | Fake account creation | 500-552 |

📘 **Pricing Reference**: https://aws.amazon.com/waf/pricing/

**Important Notes**:
- ATP and ACFP require additional configuration (login paths, field inspection) before enabling
- Bot Control has configurable inspection levels: `COMMON` (basic) or `TARGETED` (advanced)
- All paid rules have minimum monthly charges even with zero traffic

---

## 🎯 Protection Coverage

### Currently Protected Against ✅

Your WAF currently protects against:

✅ **OWASP Top 10 vulnerabilities**
- SQL injection (SQLi) - both basic and advanced patterns
- Cross-site scripting (XSS)
- Remote code execution (RCE)
- Local/remote file inclusion (LFI/RFI)
- Server-side request forgery (SSRF)
- Insecure deserialization
- XML external entity (XXE)
- Security misconfiguration

✅ **Known exploits & CVEs**
- Log4Shell (CVE-2021-44228)
- Spring4Shell (CVE-2022-22965)
- Other recently disclosed vulnerabilities (auto-updated by AWS)

✅ **Infrastructure attacks**
- Known malicious IPs (Amazon threat intelligence)
- Rate-based attacks (DDoS, brute force)
- Application-layer floods

### Not Currently Protected Against ❌

These protections are disabled but available:

❌ **Admin panel exploitation** (Admin Protection rule disabled)
❌ **Anonymous/proxy traffic** (Anonymous IP List disabled)
❌ **Automated bots** (Bot Control not enabled - paid)
❌ **Credential stuffing** (ATP not enabled - paid)
❌ **Stack-specific attacks** (WordPress, PHP, OS rules disabled)

---

## 🔧 WCU Budget Management

### Current Status

**Total Capacity**: 1,500 WCU (AWS limit for regional Web ACL)  
**Currently Used**: 1,125 WCU (75%)  
**Available**: 375 WCU (25%)

### WCU Breakdown by Rule

| Rule Name | WCU | Percentage of Total | Status |
|-----------|-----|---------------------|--------|
| Core Rule Set | 700 | 46.7% | ✅ Active |
| SQL Injection Protection | 200 | 13.3% | ✅ Active |
| Known Bad Inputs | 200 | 13.3% | ✅ Active |
| Amazon IP Reputation | 25 | 1.7% | ✅ Active |
| Rate Limiting | 0 | 0% | ✅ Active |
| **Subtotal Active** | **1,125** | **75.0%** | |
| **Available for New Rules** | **375** | **25.0%** | |

### What You Can Add with Remaining 375 WCU

Here are some recommended combinations:

**Option 1: Balanced Protection** (350 WCU)
- ✅ Admin Protection (100 WCU)
- ✅ PHP Application (100 WCU)
- ✅ POSIX OS (100 WCU)
- ✅ Bot Control (50 WCU) - Paid
- = 350 WCU used, 25 WCU remaining

**Option 2: OS-Focused** (300 WCU)
- ✅ Linux OS Protection (200 WCU)
- ✅ Anonymous IP List (50 WCU)
- ✅ Bot Control (50 WCU) - Paid
- = 300 WCU used, 75 WCU remaining

**Option 3: Application-Focused** (350 WCU)
- ✅ Admin Protection (100 WCU)
- ✅ WordPress (100 WCU)
- ✅ Anonymous IP List (50 WCU)
- ✅ Bot Control (50 WCU) - Paid
- ✅ ATP (50 WCU) - Paid
- = 350 WCU used, 25 WCU remaining

**Option 4: Maximum Free Protection** (350 WCU)
- ✅ Admin Protection (100 WCU)
- ✅ Linux OS (200 WCU)
- ✅ Anonymous IP List (50 WCU)
- = 350 WCU used, 25 WCU remaining, no paid features

### Increasing WCU Limit

If you need more than 1,500 WCU:
1. Open AWS Support case requesting limit increase
2. Can be increased up to 5,000 WCU per Web ACL
3. Typically approved within 24-48 hours
4. No additional cost for higher limit (only pay for resources used)

---

## 🔨 How to Enable/Disable Rules

### Step 1: Enable a Commented Rule

1. Open `cerpac_waf.tf` in your editor
2. Find the rule you want to enable (use line numbers from tables above)
3. Remove the `/*` at the start and `*/` at the end of the rule block
4. Verify WCU budget: `current_wcu (1125) + new_rule_wcu ≤ 1500`
5. Run `terraform plan` to preview changes
6. Run `terraform apply` to activate

**Example**: Enable Admin Protection (100 WCU)

```bash
cd /home/debian/Repos/VOS/terraform-apps/cerpac-infrastructure/environments/production
terraform plan  # Verify shows +1 resource modification
terraform apply -auto-approve
```

### Step 2: Disable an Active Rule

1. Open `cerpac_waf.tf`
2. Find the rule you want to disable
3. Wrap the entire `rule { ... }` block with `/*` and `*/`
4. Run `terraform apply`

**Example**: Disable SQL Injection Protection

```hcl
/*
rule {
  name     = "AWSManagedRulesSQLiRuleSet"
  priority = 4
  # ... rest of rule configuration
}
*/
```

### Step 3: Test Rules Without Blocking (Count Mode)

To observe rule behavior without blocking traffic:

1. Change `override_action { none {} }` to `override_action { count {} }`
2. Apply the change
3. Monitor CloudWatch metrics for `CountedRequests`
4. Check S3 logs - requests will appear in `allowed/` but with rule match info
5. After validation period (typically 24-48 hours), change back to `none {}` to enforce blocking

**Example**: Test Known Bad Inputs in count mode

```hcl
rule {
  name     = "AWSManagedRulesKnownBadInputsRuleSet"
  priority = 3

  override_action {
    count {}  # Changed from: none {}
  }
  
  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name = "AWS"
    }
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "KnownBadInputs"
    sampled_requests_enabled   = true
  }
}
```

---

## 🔍 Troubleshooting

### Problem 1: Legitimate Traffic is Being Blocked

**Symptoms**:
- Users report access denied errors
- 403 Forbidden responses
- Application functionality broken

**Diagnosis Steps**:

1. **Check S3 logs** in `s3://production-cerpac-waf-logs-<account-id>/blocked/`
   ```bash
   aws s3 ls s3://production-cerpac-waf-logs-<account-id>/blocked/ --recursive | tail -10
   aws s3 cp s3://production-cerpac-waf-logs-<account-id>/blocked/latest-file.gz - | gunzip
   ```

2. **Identify the blocking rule** from log entry:
   ```json
   {
     "timestamp": 1702900000000,
     "action": "BLOCK",
     "terminatingRuleId": "...",
     "terminatingRuleType": "MANAGED_RULE_GROUP",
     "ruleGroupList": [
       {
         "ruleGroupId": "AWSManagedRulesCommonRuleSet",
         "terminatingRule": {
           "ruleId": "GenericRFI_BODY",
           "action": "BLOCK"
         }
       }
     ]
   }
   ```

3. **Choose a solution**:

**Solution A**: Add rule exclusion (recommended)
```hcl
rule {
  name     = "AWSManagedRulesCommonRuleSet"
  priority = 1

  override_action {
    none {}
  }

  statement {
    managed_rule_group_statement {
      name        = "AWSManagedRulesCommonRuleSet"
      vendor_name = "AWS"
      
      # Exclude specific URI path
      scope_down_statement {
        not_statement {
          statement {
            byte_match_statement {
              search_string         = "/api/upload"
              positional_constraint = "STARTS_WITH"
              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
              field_to_match {
                uri_path {}
              }
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "CommonRuleSet"
    sampled_requests_enabled   = true
  }
}
```

**Solution B**: Switch to count mode temporarily
- Change `override_action { none {} }` to `override_action { count {} }`
- Monitor for false positives
- Add proper exclusions, then switch back to blocking

**Solution C**: Disable the rule entirely (not recommended)
- Only use as last resort
- Document the security risk

---

### Problem 2: No Logs Appearing in S3

**Check List**:

1. **Lambda function logs**: `/aws/lambda/production-cerpac-waf-log-router`
   ```bash
   aws logs tail /aws/lambda/production-cerpac-waf-log-router --follow
   ```

2. **Firehose delivery logs**: `/aws/firehose/cerpac-waf`
   ```bash
   aws logs tail /aws/firehose/cerpac-waf --follow
   ```

3. **Verify IAM permissions**:
   - Firehose role can invoke Lambda (`lambda:InvokeFunction`)
   - Firehose role can write to S3 (`s3:PutObject`)
   - Lambda has CloudWatch Logs permissions

4. **Check Firehose status**:
   ```bash
   aws firehose describe-delivery-stream --delivery-stream-name aws-waf-logs-production-cerpac-app-alb
   ```

---

### Problem 3: Rate Limiting Blocking Legitimate Users

**Current limit**: 1,000 requests per 5 minutes per IP

**Symptoms**:
- Power users getting blocked
- API clients hitting limits
- Load tests failing

**Solution**: Adjust rate limit

```hcl
rule {
  name     = "RateLimitPerIP"
  priority = 7

  action {
    block {}
  }

  statement {
    rate_based_statement {
      limit              = 2000  # Increased from 1000
      aggregate_key_type = "IP"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "RateLimit"
    sampled_requests_enabled   = true
  }
}
```

**Recommended limits based on use case**:
- **Public website**: 1,000-2,000 requests/5min
- **API with authenticated users**: 2,000-5,000 requests/5min
- **Internal applications**: 5,000-10,000 requests/5min

---

### Problem 4: WCU Limit Exceeded

**Error**: `WAFLimitsExceededException: The operation failed because you exceeded the WCU limit`

**Cause**: Trying to enable rules that exceed 1,500 WCU total

**Solution Steps**:

1. **Calculate current WCU**:
   - Add up all active rule WCU values
   - Current: 1,125 WCU

2. **Determine available capacity**:
   - 1,500 - 1,125 = 375 WCU available

3. **Options**:
   - **Option A**: Disable lower-priority rules to free capacity
   - **Option B**: Request limit increase via AWS Support (up to 5,000 WCU)
   - **Option C**: Re-prioritize which rules are most important

4. **Request limit increase** (if needed):
   ```
   AWS Support Console → Create Case → Service Limit Increase
   → Service: WAF
   → Limit Type: WCU per Web ACL
   → New Limit: 5000
   → Use Case: Describe your requirements
   ```

---

## 📊 Monitoring & Metrics

### CloudWatch Metrics

View in AWS Console: **CloudWatch → Metrics → WAF → Regional → WebACL**

**Key Metrics to Monitor**:

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `BlockedRequests` | Requests blocked by WAF | Sudden spike (>1000% increase) |
| `AllowedRequests` | Requests that passed | Sudden drop (>50% decrease) |
| `CountedRequests` | Requests matched but not blocked | >0 when all rules in enforcement mode |
| `RateLimit` | Requests blocked by rate limiting | Sustained high values |

**Per-Rule Metrics**:
- `CommonRuleSet` - OWASP Top 10 blocks
- `SQLiRuleSet` - SQL injection blocks
- `KnownBadInputs` - CVE/exploit blocks
- `IpReputationList` - Malicious IP blocks

### Setting Up CloudWatch Alarms

**Example**: Alert on sudden spike in blocked requests

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WAF-High-Block-Rate" \
  --alarm-description "Alert when WAF blocks exceed normal threshold" \
  --metric-name BlockedRequests \
  --namespace AWS/WAFV2 \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 1000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=Rule,Value=ALL Name=WebACL,Value=production-cerpac-waf
```

---

## 📚 Complete Rule Inventory

### Currently Active Rules ✅

| Priority | Rule Name | WCU | Status | Last Modified |
|----------|-----------|-----|--------|---------------|
| 1 | Core Rule Set (OWASP Top 10) | 700 | ✅ Active | Initial deployment |
| 3 | Known Bad Inputs | 200 | ✅ Active | Initial deployment |
| 4 | SQL Injection Protection | 200 | ✅ Active | Initial deployment |
| 5 | Amazon IP Reputation List | 25 | ✅ Active | Initial deployment |
| 7 | Rate Limiting (Per IP) | 0 | ✅ Active | Initial deployment |

### Recently Disabled Rules 💤

| Priority | Rule Name | WCU | Status | Disabled Date |
|----------|-----------|-----|--------|---------------|
| 2 | Admin Protection | 100 | 💤 Disabled | Dec 18, 2025 |
| 6 | Anonymous IP List | 50 | 💤 Disabled | Dec 18, 2025 |

### Available Phase 2 Rules 💤

| Priority | Rule Name | WCU | Status |
|----------|-----------|-----|--------|
| 10 | WordPress Application | 100 | 💤 Commented out |
| 11 | PHP Application | 100 | 💤 Commented out |
| 12 | Linux OS Protection | 200 | 💤 Commented out |
| 13 | POSIX OS Protection | 100 | 💤 Commented out |
| 14 | Windows OS Protection | 200 | 💤 Commented out |

### Available Phase 3 Rules 💰💤

| Priority | Rule Name | WCU | Cost | Status |
|----------|-----------|-----|------|--------|
| 20 | Bot Control | 50 | $10/mo + usage | 💤 Commented out |
| 21 | Account Takeover Prevention (ATP) | 50 | $10/mo + usage | 💤 Commented out |
| 22 | Account Creation Fraud Prevention (ACFP) | 50 | $10/mo + usage | 💤 Commented out |

---

## 📘 Additional Resources

- **Main Configuration File**: `production-infrastructure/cerpac_waf.tf`
- **Architecture Document**: `production-infrastructure/cerpac_waf.md`
- **AWS WAF Documentation**: https://docs.aws.amazon.com/waf/
- **Managed Rule Groups List**: https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html
- **WAF Pricing Calculator**: https://aws.amazon.com/waf/pricing/
- **Security Best Practices**: https://docs.aws.amazon.com/waf/latest/developerguide/security-best-practices.html

---

**Last Updated**: December 18, 2025  
**Configuration Version**: Phase 1 Active (1,125 WCU)  
**Total Active Rules**: 5 of 17 available  
**WCU Utilization**: 75% (1,125 / 1,500)  
**Available Capacity**: 375 WCU

