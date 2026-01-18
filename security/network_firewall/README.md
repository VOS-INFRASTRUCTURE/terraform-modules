# AWS Network Firewall Module

## ⚠️ IMPORTANT: Read Before Deploying

**This module is expensive (~$350-500/month) and likely NOT needed for most HTTP/HTTPS web applications.**

Before deploying, read:
- [AWS Network Firewall Analysis](../../documentations/security/aws_network_firewall_analysis.md)
- [AWS Security Services Comparison](../../documentations/security/aws_security_services_comparison.md)

**For standard web applications with HTTP/HTTPS traffic only, use AWS WAF instead** (much cheaper at ~$25/month and better suited for web traffic).

---

## Overview

AWS Network Firewall is a stateful, managed network firewall and intrusion detection/prevention service (IDS/IPS) that operates at the VPC perimeter to filter network traffic.

### What This Module Deploys

```
┌─────────────────────────────────────────────────────────────┐
│  VPC                                                         │
│                                                              │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │ Firewall Subnet  │      │ Firewall Subnet  │            │
│  │  (AZ-1)          │      │  (AZ-2)          │            │
│  │                  │      │                  │            │
│  │  ┌────────────┐  │      │  ┌────────────┐  │            │
│  │  │ Firewall   │  │      │  │ Firewall   │  │            │
│  │  │ Endpoint   │  │      │  │ Endpoint   │  │            │
│  │  └─────┬──────┘  │      │  └─────┬──────┘  │            │
│  └────────┼─────────┘      └────────┼─────────┘            │
│           │                         │                       │
│           └────────────┬────────────┘                       │
│                        │                                     │
│                        ▼                                     │
│           ┌─────────────────────────┐                       │
│           │  Firewall Policy        │                       │
│           │  - Domain filtering     │                       │
│           │  - IP blocking          │                       │
│           │  - Protocol filtering   │                       │
│           │  - Suricata IDS/IPS     │                       │
│           └─────────────────────────┘                       │
│                        │                                     │
│                        ▼                                     │
│           ┌─────────────────────────┐                       │
│           │  Application Subnets    │                       │
│           │  (EC2, ECS, etc.)       │                       │
│           └─────────────────────────┘                       │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
            ┌────────────────────────┐
            │  CloudWatch Logs       │
            │  - Flow logs           │
            │  - Alert logs (IDS)    │
            └────────────────────────┘
```

---

## When to Use This Module

### ✅ Use Network Firewall If You Have:

1. **Multi-protocol traffic** (not just HTTP/HTTPS)
   - FTP, SSH, RDP, custom UDP protocols
   - Example: Gaming servers, VoIP, video streaming

2. **Outbound domain filtering requirements**
   - Block EC2 from accessing specific domains
   - Allow-list only approved external APIs
   - Example: "Only allow .amazonaws.com and .github.com"

3. **Complex network topology**
   - Transit Gateway with multiple VPCs
   - Hub-and-spoke architecture
   - East-west traffic inspection between VPCs

4. **PCI DSS Level 1 compliance**
   - Requirement 11.4: Network-based IDS/IPS
   - Deep packet inspection

5. **Advanced threat prevention**
   - Suricata IDS/IPS rules
   - Custom signature-based detection
   - Protocol anomaly detection

### ❌ Don't Use Network Firewall If:

1. **Your traffic is HTTP/HTTPS only** → Use AWS WAF instead ($25/month)
2. **Budget is limited** → Network Firewall costs $350+/month
3. **Simple web application** → WAF + Security Groups + GuardDuty are sufficient
4. **Standard OWASP protection needed** → AWS WAF handles this better

---

## Features

### Rule Groups

| Rule Group | Purpose | Default |
|-----------|---------|---------|
| **Domain Filtering** | Allow/block specific domains (e.g., ".amazonaws.com") | ✅ Enabled |
| **IP Filtering** | Block malicious IP ranges | ✅ Enabled |
| **Protocol Filtering** | Block insecure protocols (FTP, Telnet, SMTP) | ✅ Enabled |
| **Suricata IDS/IPS** | Detect attacks using Suricata rules | ✅ Enabled |

### Logging

| Log Type | Description | Storage |
|----------|-------------|---------|
| **Flow Logs** | Network traffic metadata (source, destination, ports) | CloudWatch or S3 |
| **Alert Logs** | IDS/IPS alerts (detected threats) | CloudWatch or S3 |

### Protection Settings

| Setting | Purpose | Default |
|---------|---------|---------|
| **Policy Change Protection** | Prevent accidental policy changes | ❌ Disabled |
| **Subnet Change Protection** | Prevent subnet association changes | ❌ Disabled |
| **Delete Protection** | Prevent firewall deletion | ✅ Enabled |

---

## Usage

### Example 1: Basic Network Firewall (Disabled by Default)

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "myapp"
  enable_network_firewall = false  # Keep disabled unless you have specific requirements

  # VPC configuration (required if enabled)
  vpc_id     = "vpc-12345678"
  subnet_ids = []  # Dedicated firewall subnets (one per AZ)
}
```

### Example 2: Enable with Domain Filtering

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "myapp"
  enable_network_firewall = true

  # VPC configuration
  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]  # Dedicated subnets

  # Domain filtering (allow-list)
  enable_domain_filtering = true
  allowed_domains = [
    ".amazonaws.com",
    ".github.com",
    ".npmjs.org",
    ".docker.com"
  ]

  # IP filtering
  enable_ip_filtering = true
  blocked_ip_ranges = [
    "192.0.2.0/24",      # Example malicious range
    "198.51.100.0/24"    # Example C2 server range
  ]

  # Protocol filtering
  enable_protocol_filtering = true
  blocked_protocols        = ["FTP", "TELNET"]

  # Suricata IDS/IPS
  enable_suricata_rules = true

  # Logging
  enable_flow_logs  = true
  enable_alert_logs = true
  log_destination_type = "CloudWatchLogs"
  log_retention_days   = 90

  tags = {
    CostCenter = "Security"
    Compliance = "PCI-DSS"
  }
}
```

### Example 3: Custom Suricata Rules

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "myapp"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]

  # Custom Suricata rules
  enable_suricata_rules       = true
  enable_custom_suricata_rules = true
  custom_suricata_rules       = <<-EOT
    # Custom rule: Block specific malware signature
    drop ip any any -> any any (msg:"Known Ransomware"; content:"|4D 5A|"; offset:0; depth:2; sid:2000001; rev:1;)
    
    # Custom rule: Alert on suspicious DNS queries
    alert dns any any -> any 53 (msg:"Suspicious DNS Query"; content:"evil.com"; sid:2000002; rev:1;)
    
    # Custom rule: Detect crypto mining traffic
    alert tcp any any -> any any (msg:"Crypto Mining Pool"; content:"stratum+tcp"; sid:2000003; rev:1;)
  EOT
}
```

### Example 4: Log to S3

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "myapp"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]

  # Log to S3 instead of CloudWatch
  enable_flow_logs     = true
  enable_alert_logs    = true
  log_destination_type = "S3"
  s3_bucket_name       = "my-security-logs-bucket"
}
```

---

## Variables

### Required Variables (if enabled)

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `env` | Environment name | `string` | n/a |
| `project_id` | Project identifier | `string` | n/a |
| `vpc_id` | VPC ID for firewall deployment | `string` | `""` |
| `subnet_ids` | Firewall subnet IDs (one per AZ) | `list(string)` | `[]` |

### Optional Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_network_firewall` | Enable Network Firewall | `bool` | `false` |
| `enable_domain_filtering` | Enable domain filtering | `bool` | `true` |
| `allowed_domains` | Allowed domains list | `list(string)` | See variables.tf |
| `enable_ip_filtering` | Enable IP filtering | `bool` | `true` |
| `blocked_ip_ranges` | Blocked IP ranges | `list(string)` | `[]` |
| `enable_protocol_filtering` | Enable protocol filtering | `bool` | `true` |
| `blocked_protocols` | Protocols to block | `list(string)` | `["FTP", "TELNET"]` |
| `enable_suricata_rules` | Enable Suricata IDS/IPS | `bool` | `true` |
| `enable_flow_logs` | Enable flow logs | `bool` | `true` |
| `enable_alert_logs` | Enable alert logs | `bool` | `true` |
| `log_destination_type` | Log destination (CloudWatchLogs, S3) | `string` | `"CloudWatchLogs"` |
| `log_retention_days` | Log retention days | `number` | `90` |
| `delete_protection` | Enable delete protection | `bool` | `true` |

See [variables.tf](./variables.tf) for complete list.

---

## Outputs

| Name | Description |
|------|-------------|
| `network_firewall` | Complete firewall configuration |
| `firewall_endpoint_ids` | Firewall endpoint IDs by AZ (for route tables) |
| `estimated_monthly_cost` | Cost estimate |

### Output Example

```hcl
{
  enabled       = true
  firewall_id   = "fw-12345678"
  firewall_arn  = "arn:aws:network-firewall:..."
  firewall_name = "production-myapp-network-firewall"
  
  rule_groups = {
    domain_filtering = {
      enabled = true
      arn     = "arn:aws:network-firewall:..."
      name    = "production-myapp-domain-filter"
    }
    # ... other rule groups
  }
  
  logging = {
    flow_logs = {
      enabled        = true
      log_group_name = "/aws/networkfirewall/production-myapp/flow"
    }
  }
}
```

---

## Cost Breakdown

### Monthly Cost Estimate

| Component | Cost | Notes |
|-----------|------|-------|
| **Firewall Endpoint (per AZ)** | $288/month | $0.395/hour × 730 hours |
| **Data Processing** | $0.065/GB | Charged per GB processed |
| **CloudWatch Logs** | $0.50/GB | Ingestion + storage |

**Example for 2 AZs:**
```
Firewall endpoints: 2 × $288 = $576/month
Data processing:    100GB × $0.065 = $6.50/month
CloudWatch logs:    10GB × $0.50 = $5/month
────────────────────────────────────────────
Total:              ~$587.50/month
```

**Compare to AWS WAF:** ~$25/month for web application protection

---

## Post-Deployment Configuration

### Step 1: Update Route Tables

After deployment, you must update route tables to route traffic through firewall endpoints:

```hcl
resource "aws_route" "to_firewall" {
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = module.network_firewall.firewall_endpoint_ids["us-east-1a"]
}
```

### Step 2: Monitor Logs

**View flow logs:**
```bash
aws logs tail /aws/networkfirewall/production-myapp/flow --follow
```

**View alert logs (IDS/IPS):**
```bash
aws logs tail /aws/networkfirewall/production-myapp/alert --follow
```

### Step 3: Review Findings

Network Firewall integrates with Security Hub. Check:
- AWS Console → Security Hub → Findings
- Filter by: "Network Firewall"

---

## Troubleshooting

### Issue 1: High Costs

**Symptom:** Monthly bill exceeds $500

**Solution:**
1. Check data processing volume: `aws cloudwatch get-metric-statistics ...`
2. Consider moving to S3 for cheaper log storage
3. Reduce log retention period
4. Evaluate if you actually need Network Firewall (see comparison docs)

### Issue 2: Legitimate Traffic Blocked

**Symptom:** Application cannot reach external API

**Solution:**
1. Check flow logs for dropped connections
2. Add domain to `allowed_domains` list
3. Update firewall policy: `terraform apply`

### Issue 3: No Logs Appearing

**Symptom:** CloudWatch log groups empty

**Solution:**
1. Verify logging is enabled: `enable_flow_logs = true`
2. Check firewall is receiving traffic (route tables configured?)
3. Verify IAM permissions for log delivery

---

## Best Practices

### 1. Use Dedicated Subnets

Create separate subnets for firewall endpoints (don't reuse application subnets).

### 2. Enable Delete Protection

```hcl
delete_protection = true  # Prevent accidental deletion
```

### 3. Start with Alert Mode

Test Suricata rules in alert mode before blocking:
```hcl
# In Suricata rules, use "alert" instead of "drop" initially
alert http any any -> any any (msg:"Test rule"; ...)
```

### 4. Monitor Costs

Set up budget alerts:
```bash
aws budgets create-budget --budget file://network-firewall-budget.json
```

### 5. Use Domain Allow-Lists

Prefer allow-lists over deny-lists for better security:
```hcl
allowed_domains = [
  ".amazonaws.com",
  ".github.com",
  # Only approved domains
]
```

---

## Compliance Mapping

| Framework | Control | Requirement |
|-----------|---------|-------------|
| **PCI DSS** | 11.4 | Network-based IDS/IPS |
| **NIST 800-53** | SI-4 | Information system monitoring |
| **CIS AWS** | 4.1 | Ensure network ACLs are restrictive |
| **SOC 2** | CC6.1 | Logical access controls |

---

## Alternatives to Consider

Before deploying Network Firewall, consider these alternatives:

| Use Case | Alternative | Cost | Effectiveness |
|----------|-------------|------|---------------|
| **Web application protection** | AWS WAF | $25/month | ✅ Better for HTTP/HTTPS |
| **Threat detection** | GuardDuty | $10/month | ✅ ML-based detection |
| **Network access control** | Security Groups | FREE | ✅ Sufficient for most cases |
| **Compliance monitoring** | Security Hub | $15/month | ✅ 140+ automated checks |

**For 95% of web applications, the combination of WAF + GuardDuty + Security Groups is sufficient and 10x cheaper.**

---

## Related Documentation

- [AWS Network Firewall Analysis](../../documentations/security/aws_network_firewall_analysis.md) - Detailed comparison and decision guide
- [AWS Security Services Comparison](../../documentations/security/aws_security_services_comparison.md) - When to use each service
- [AWS WAF Module](../waf/) - Alternative for HTTP/HTTPS protection
- [GuardDuty Module](../guard_duty/) - Threat detection alternative

---

## Summary

**AWS Network Firewall is a powerful but expensive service.**

**Use it only if you have:**
- Multi-protocol traffic (not just HTTP/HTTPS)
- Outbound domain filtering requirements
- Complex multi-VPC architecture
- PCI DSS Level 1 compliance needs

**For standard web applications, use AWS WAF instead** - it's cheaper, easier to manage, and better suited for HTTP/HTTPS traffic.

**Default state of this module: DISABLED (`enable_network_firewall = false`)**

Enable only after reading the analysis documentation and confirming you have a legitimate use case that justifies the cost.

