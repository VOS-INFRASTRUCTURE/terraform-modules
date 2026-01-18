# AWS Network Firewall - Usage Examples

## Example 1: Disabled (Default - Recommended for Most Use Cases)

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env        = "production"
  project_id = "cerpac"

  # Keep disabled unless you have specific requirements
  enable_network_firewall = false

  tags = {
    ManagedBy = "Terraform"
  }
}
```

**Use Case:** Standard web application with HTTP/HTTPS traffic only. Use AWS WAF instead.

**Monthly Cost:** $0

---

## Example 2: Basic Network Firewall with Domain Filtering

```hcl
# First, create dedicated firewall subnets
resource "aws_subnet" "firewall_1a" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.255.0/28"  # Small subnet for firewall endpoint
  availability_zone = "us-east-1a"

  tags = {
    Name = "production-firewall-subnet-1a"
  }
}

resource "aws_subnet" "firewall_1b" {
  vpc_id            = var.vpc_id
  cidr_block        = "10.0.255.16/28"
  availability_zone = "us-east-1b"

  tags = {
    Name = "production-firewall-subnet-1b"
  }
}

# Deploy Network Firewall
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "cerpac"
  enable_network_firewall = true

  # VPC configuration
  vpc_id = var.vpc_id
  subnet_ids = [
    aws_subnet.firewall_1a.id,
    aws_subnet.firewall_1b.id
  ]

  # Domain filtering (allow only approved domains)
  enable_domain_filtering = true
  allowed_domains = [
    ".amazonaws.com",
    ".github.com",
    ".npmjs.org",
    ".docker.com"
  ]

  # Logging
  enable_flow_logs       = true
  enable_alert_logs      = true
  log_destination_type   = "CloudWatchLogs"
  log_retention_days     = 90

  # Protection
  delete_protection = true

  tags = {
    CostCenter = "Security"
    Compliance = "Required"
  }
}

# Update route tables to route traffic through firewall
resource "aws_route" "app_to_firewall" {
  route_table_id  = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id = module.network_firewall.firewall_endpoint_ids["us-east-1a"]
}
```

**Use Case:** Multi-VPC architecture requiring centralized outbound filtering.

**Monthly Cost:** ~$576 (2 AZs) + data processing

---

## Example 3: Block Malicious IPs and Insecure Protocols

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "secure-app"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]

  # IP filtering (block known malicious ranges)
  enable_ip_filtering = true
  blocked_ip_ranges = [
    "192.0.2.0/24",      # Example malicious IP range
    "198.51.100.0/24",   # Example C2 server range
    "203.0.113.0/24"     # Example botnet range
  ]

  # Protocol filtering (block insecure protocols)
  enable_protocol_filtering = true
  blocked_protocols = [
    "FTP",     # Unencrypted file transfer
    "TELNET",  # Unencrypted remote access
    "SMTP"     # Unencrypted email (port 25)
  ]

  # Suricata IDS/IPS
  enable_suricata_rules = true

  # Logging
  enable_flow_logs     = true
  enable_alert_logs    = true
  log_destination_type = "CloudWatchLogs"
}
```

**Use Case:** High-security environment requiring protocol and IP blocking.

**Monthly Cost:** ~$576 (2 AZs) + data processing

---

## Example 4: Custom Suricata Rules for Threat Detection

```hcl
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "finance-app"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]

  # Custom Suricata IDS/IPS rules
  enable_suricata_rules        = true
  enable_custom_suricata_rules = true
  custom_suricata_rules        = <<-EOT
    # Alert on SQL injection attempts
    alert http any any -> any any (msg:"SQL Injection Attempt"; flow:established,to_server; content:"SELECT"; http_uri; content:"FROM"; distance:0; http_uri; sid:1000001; rev:1;)
    
    # Alert on XSS attempts
    alert http any any -> any any (msg:"XSS Attack Detected"; flow:established,to_server; content:"<script"; http_uri; sid:1000002; rev:1;)
    
    # Drop known ransomware signatures
    drop ip any any -> any any (msg:"Ransomware Detected"; content:"|4D 5A 90 00|"; offset:0; depth:4; sid:1000003; rev:1;)
    
    # Alert on cryptocurrency mining
    alert tcp any any -> any any (msg:"Crypto Mining Pool Connection"; content:"stratum+tcp"; sid:1000004; rev:1;)
    
    # Alert on suspicious DNS queries (DGA domains)
    alert dns any any -> any 53 (msg:"Possible DGA Domain"; content:"|01 00 00 01|"; offset:2; depth:4; pcre:"/[a-z]{20,}/"; sid:1000005; rev:1;)
    
    # Drop traffic to known C2 servers
    drop ip any any -> 198.51.100.0/24 any (msg:"C2 Server Communication Blocked"; sid:1000006; rev:1;)
  EOT

  enable_flow_logs  = true
  enable_alert_logs = true
}
```

**Use Case:** PCI DSS compliance requiring network-based IDS/IPS.

**Monthly Cost:** ~$576 (2 AZs) + data processing

---

## Example 5: Log to S3 for Long-Term Retention

```hcl
# Create S3 bucket for firewall logs
resource "aws_s3_bucket" "firewall_logs" {
  bucket = "production-network-firewall-logs"

  tags = {
    Purpose = "NetworkFirewall-Logs"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firewall_logs" {
  bucket = aws_s3_bucket.firewall_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Deploy Network Firewall with S3 logging
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "cerpac"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b"]

  # Log to S3 (cheaper for long-term retention)
  enable_flow_logs     = true
  enable_alert_logs    = true
  log_destination_type = "S3"
  s3_bucket_name       = aws_s3_bucket.firewall_logs.id

  enable_domain_filtering = true
  allowed_domains = [
    ".amazonaws.com",
    ".github.com"
  ]
}
```

**Use Case:** Cost optimization - S3 storage is cheaper than CloudWatch for large log volumes.

**Monthly Cost:** ~$576 (2 AZs) + data processing + S3 storage

---

## Example 6: Multi-VPC with Transit Gateway

```hcl
# Inspection VPC (dedicated for Network Firewall)
module "inspection_vpc" {
  source = "../../vpc"

  name       = "inspection-vpc"
  cidr_block = "10.100.0.0/16"

  # Firewall subnets (one per AZ)
  firewall_subnets = {
    "us-east-1a" = "10.100.1.0/28"
    "us-east-1b" = "10.100.1.16/28"
  }
}

# Network Firewall in inspection VPC
module "network_firewall" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "multi-vpc"
  enable_network_firewall = true

  vpc_id     = module.inspection_vpc.vpc_id
  subnet_ids = module.inspection_vpc.firewall_subnet_ids

  # Strict domain filtering for all VPCs
  enable_domain_filtering = true
  allowed_domains = [
    ".amazonaws.com",
    ".company.com"
  ]

  # Block all insecure protocols
  enable_protocol_filtering = true
  blocked_protocols        = ["FTP", "TELNET", "SMTP"]

  # Suricata IDS/IPS
  enable_suricata_rules = true

  enable_flow_logs  = true
  enable_alert_logs = true
}

# Transit Gateway attachment
resource "aws_ec2_transit_gateway_vpc_attachment" "inspection" {
  subnet_ids         = module.inspection_vpc.firewall_subnet_ids
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = module.inspection_vpc.vpc_id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
}
```

**Use Case:** Hub-and-spoke architecture with centralized traffic inspection.

**Monthly Cost:** ~$576 (2 AZs) + Transit Gateway ($36/month/attachment) + data processing

---

## Example 7: PCI DSS Compliance Configuration

```hcl
module "network_firewall_pci" {
  source = "../../security/network_firewall"

  env                     = "production"
  project_id              = "payment-app"
  enable_network_firewall = true

  vpc_id     = "vpc-12345678"
  subnet_ids = ["subnet-firewall-1a", "subnet-firewall-1b", "subnet-firewall-1c"]  # 3 AZs for HA

  # PCI DSS Requirement 1.3: Restrict inbound/outbound traffic
  enable_domain_filtering = true
  allowed_domains = [
    ".pci-approved-processor.com",
    ".payment-gateway.com",
    ".amazonaws.com"
  ]

  # PCI DSS Requirement 2.2.2: Block insecure protocols
  enable_protocol_filtering = true
  blocked_protocols = [
    "FTP",
    "TELNET",
    "SMTP"
  ]

  # PCI DSS Requirement 11.4: IDS/IPS
  enable_suricata_rules        = true
  enable_custom_suricata_rules = true
  custom_suricata_rules        = <<-EOT
    # PCI DSS specific rules
    alert http any any -> any any (msg:"PCI: Credit Card Pattern in URI"; flow:established,to_server; content:"card"; http_uri; pcre:"/\d{13,19}/"; sid:2000001; rev:1;)
    alert http any any -> any any (msg:"PCI: SQL Injection"; flow:established,to_server; content:"SELECT"; http_uri; sid:2000002; rev:1;)
  EOT

  # PCI DSS Requirement 10.2: Logging
  enable_flow_logs     = true
  enable_alert_logs    = true
  log_destination_type = "CloudWatchLogs"
  log_retention_days   = 365  # PCI DSS requires 1 year minimum

  # Enable all protections
  firewall_policy_change_protection = true
  subnet_change_protection          = true
  delete_protection                 = true

  tags = {
    Compliance = "PCI-DSS-v4.0"
    DataClass  = "Cardholder-Data"
  }
}
```

**Use Case:** PCI DSS Level 1 merchant requiring network-based IDS/IPS.

**Monthly Cost:** ~$864 (3 AZs) + data processing

---

## Cost Comparison Across Examples

| Example | AZs | Monthly Cost | Use Case |
|---------|-----|--------------|----------|
| **Example 1** (Disabled) | 0 | $0 | Standard web app (use WAF) |
| **Example 2** (Basic) | 2 | ~$576 | Multi-VPC outbound filtering |
| **Example 3** (IP/Protocol) | 2 | ~$576 | High-security environment |
| **Example 4** (Custom Suricata) | 2 | ~$576 | Advanced threat detection |
| **Example 5** (S3 Logs) | 2 | ~$576 + S3 | Cost-optimized logging |
| **Example 6** (Transit Gateway) | 2 | ~$612 | Hub-and-spoke architecture |
| **Example 7** (PCI DSS) | 3 | ~$864 | PCI DSS compliance |

**For comparison:**
- AWS WAF: ~$25/month
- GuardDuty: ~$10/month
- Security Groups: FREE

---

## Monitoring Network Firewall

### View Logs in CloudWatch

```bash
# Flow logs
aws logs tail /aws/networkfirewall/production-cerpac/flow --follow

# Alert logs (IDS/IPS)
aws logs tail /aws/networkfirewall/production-cerpac/alert --follow
```

### Query for Blocked Traffic

```bash
# CloudWatch Insights query
aws logs start-query \
  --log-group-name "/aws/networkfirewall/production-cerpac/flow" \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, event.src_ip, event.dest_ip, event.dest_port | filter event.action = "DROP"'
```

### View Metrics

```bash
# Packets processed
aws cloudwatch get-metric-statistics \
  --namespace AWS/NetworkFirewall \
  --metric-name PacketsProcessed \
  --dimensions Name=FirewallName,Value=production-cerpac-network-firewall \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

---

## Common Patterns

### Pattern 1: Gradual Rollout

Start with alert-only mode, then enable blocking:

```hcl
# Phase 1: Alert only (monitor for false positives)
enable_stateful_default_actions = ["aws:alert_strict"]

# Phase 2: After 1 week, enable blocking
enable_stateful_default_actions = ["aws:drop_strict", "aws:alert_established"]
```

### Pattern 2: Domain Allow-List with Exceptions

```hcl
allowed_domains = [
  # Core AWS services
  ".amazonaws.com",
  
  # Package managers
  ".npmjs.org",
  ".docker.com",
  ".ubuntu.com",
  
  # CI/CD
  ".github.com",
  ".gitlab.com",
  
  # Monitoring
  ".datadog.com",
  ".newrelic.com"
]
```

### Pattern 3: Layered Security

Combine with other security services:

```hcl
# Layer 1: WAF (application layer)
module "waf" {
  source = "../../security/waf"
  # ...
}

# Layer 2: Network Firewall (network layer)
module "network_firewall" {
  source = "../../security/network_firewall"
  # ...
}

# Layer 3: GuardDuty (threat detection)
module "guardduty" {
  source = "../../security/guard_duty"
  # ...
}
```

---

## Troubleshooting

### Issue: High Data Processing Costs

**Symptom:** Data processing charges exceed $100/month

**Solution:**
1. Check traffic volume: `aws networkfirewall describe-firewall --firewall-name ...`
2. Consider moving logs to S3 (cheaper)
3. Reduce log verbosity: `enable_flow_logs = false` (keep alert logs only)

### Issue: Legitimate Traffic Blocked

**Symptom:** Application cannot reach external API

**Steps:**
1. Check alert logs for denied connections
2. Add domain to `allowed_domains`
3. Apply changes: `terraform apply`

### Issue: No Alerts Generated

**Symptom:** Alert log group is empty

**Verification:**
1. Confirm Suricata rules are enabled: `enable_suricata_rules = true`
2. Test with known pattern: `curl http://example.com/../../../etc/passwd`
3. Check flow logs for traffic

---

## Next Steps After Deployment

1. ✅ Update route tables to route through firewall endpoints
2. ✅ Monitor logs for 1 week to identify false positives
3. ✅ Tune domain allow-list based on actual traffic
4. ✅ Set up CloudWatch alarms for high alert volume
5. ✅ Review costs weekly during initial deployment
6. ✅ Document approved domains and protocols

---

## When NOT to Use These Examples

❌ **Don't deploy if:**
- Your traffic is HTTP/HTTPS only (use AWS WAF)
- You don't need outbound domain filtering
- Budget is limited ($576+/month is too expensive)
- You have simple web application architecture

✅ **Do deploy if:**
- You have multi-protocol traffic (FTP, SSH, custom UDP)
- You need centralized outbound filtering
- PCI DSS Level 1 compliance required
- Multi-VPC hub-and-spoke architecture

**For 95% of use cases, AWS WAF + GuardDuty + Security Groups is sufficient and 10x cheaper!**

