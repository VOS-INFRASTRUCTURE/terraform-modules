# AWS S3 VPC Endpoints: Gateway vs Interface - Complete Guide

**Last Updated:** January 27, 2026

## 📋 Table of Contents

1. [TL;DR - Quick Decision Guide](#tldr---quick-decision-guide)
2. [The DNS Gotcha (Why Gateway "Feels Broken")](#the-dns-gotcha-why-gateway-feels-broken)
3. [Gateway vs Interface: Full Comparison](#gateway-vs-interface-full-comparison)
4. [When to Use Each Type](#when-to-use-each-type)
5. [Cost Comparison](#cost-comparison)
6. [Implementation in This Module](#implementation-in-this-module)
7. [Troubleshooting](#troubleshooting)

---

## TL;DR - Quick Decision Guide

### ✅ Use S3 **Gateway** Endpoint When:
- EC2 is in **public subnet** (has internet via IGW)
- EC2 is in **private subnet WITH NAT Gateway**
- Access is from **AWS-managed services** (Glue, EMR, Backup)
- Cost optimization is critical (Gateway is **FREE**)

### ✅ Use S3 **Interface** Endpoint When:
- EC2 is in **private subnet WITHOUT NAT Gateway**
- You want `aws s3 ls s3://bucket` to "just work"
- You need **private DNS** for normal SDK/CLI access
- You're willing to pay **~$7.20/month** for convenience

---

## The DNS Gotcha (Why Gateway "Feels Broken")

### ❌ Common Misconception:
> "S3 Gateway endpoints require internet access / NAT Gateway to work"

### ✅ The Truth:
**S3 Gateway endpoints do NOT require internet.** They work at the **route table level** and are designed specifically to avoid internet routing.

### 🔍 The Real Problem: DNS + Routing Mismatch

| Endpoint Type | Needs NAT/IGW | Private DNS | `aws s3 ls` in Private Subnet |
|---------------|---------------|-------------|-------------------------------|
| **Gateway**   | ❌ No         | ❌ No       | ❌ Often hangs/fails          |
| **Interface** | ❌ No         | ✅ Yes      | ✅ Works normally             |

### Why S3 Gateway "Feels Broken" (But Technically Isn't)

#### How S3 Gateway Works:
1. **Route table level**: Matches traffic using AWS-managed prefix lists
2. **No DNS modification**: Bucket hostnames still resolve to **public IPs**
3. **No private IPs**: Gateway endpoint has no ENI, no private IP

#### What Actually Happens in Private Subnet (No NAT):

```bash
$ aws s3 ls s3://my-bucket

# Step 1: DNS resolution
my-bucket.s3.eu-west-2.amazonaws.com → 52.95.128.x (public IP)

# Step 2: EC2 tries to connect to public IP
# ❌ EC2 is in private subnet, no route to internet
# ⏳ Connection hangs...

# The problem:
# - Routing WOULD work if traffic reached the prefix list match
# - But it never gets that far because:
#   - DNS gives public IP
#   - Private subnet has no route to public IP ranges
#   - Traffic dies before prefix list matching happens
```

#### What Works (The Routing is Correct):

```bash
# If you could force the SDK to use the prefix list ranges directly
# (which you can't in normal usage), routing would work fine.
# This is why AWS-managed services (Glue, EMR) work with Gateway endpoints
# — they have custom network integration.
```

### The Interface Endpoint Solution:

```bash
$ aws s3 ls s3://my-bucket

# Step 1: DNS resolution (Private DNS enabled)
my-bucket.s3.eu-west-2.amazonaws.com → 10.0.1.50 (private IP of ENI)

# Step 2: EC2 connects to private IP
# ✅ Works! Traffic stays in VPC, uses Interface endpoint ENI

# No public IP, no internet routing, no NAT needed
```

---

## Gateway vs Interface: Full Comparison

| Feature                          | **Gateway Endpoint**                    | **Interface Endpoint**                   |
|----------------------------------|-----------------------------------------|------------------------------------------|
| **Type**                         | Gateway (route table)                   | Interface (ENI in subnet)                |
| **Cost**                         | ✅ **FREE**                             | 💰 ~$7.20/month per AZ                   |
| **Private DNS**                  | ❌ No                                   | ✅ Yes                                   |
| **Private IPs**                  | ❌ No (uses AWS prefix lists)           | ✅ Yes (ENI with private IP)             |
| **Supports Services**            | S3, DynamoDB only                       | 100+ AWS services                        |
| **Requires NAT for CLI/SDK**     | ⚠️ Yes (due to DNS)                     | ❌ No                                    |
| **Works in Isolated Private**    | ❌ No (DNS issue)                       | ✅ Yes                                   |
| **Endpoint Policy Support**      | ✅ Yes                                  | ❌ No                                    |
| **Data Transfer Cost**           | ✅ FREE (same region)                   | ✅ FREE (same region)                    |
| **Setup Complexity**             | ✅ Simple (route table association)     | ⚠️ Moderate (subnet, SG, DNS)            |
| **Best For**                     | Cost optimization, AWS-managed services | Normal CLI/SDK access, fully private    |

---

## When to Use Each Type

### 🟢 Use S3 **Gateway** Endpoint

#### ✅ Scenario 1: Public Subnet with Internet Gateway
```
EC2 (public subnet) → IGW → Internet
                   ↓
                S3 Gateway Endpoint (for cost savings)
```
- DNS resolves to public IP
- IGW provides route to internet
- Gateway endpoint saves data transfer costs
- **Works perfectly**

#### ✅ Scenario 2: Private Subnet WITH NAT Gateway
```
EC2 (private subnet) → NAT Gateway → IGW → Internet
                    ↓
                 S3 Gateway Endpoint (for cost savings)
```
- DNS resolves to public IP
- NAT provides route to internet IP ranges
- Gateway endpoint intercepts S3 traffic (cheaper than NAT data transfer)
- **Works perfectly**

#### ✅ Scenario 3: AWS-Managed Services
```
AWS Glue / EMR / Backup → S3 Gateway Endpoint
```
- These services have custom network integration
- They work correctly with Gateway endpoints
- **Works perfectly**

### 🟢 Use S3 **Interface** Endpoint

#### ✅ Scenario 1: Fully Private Subnet (No NAT, No IGW)
```
EC2 (private subnet, no NAT) → S3 Interface Endpoint (private DNS)
```
- DNS resolves to private IP (10.x.x.x)
- No internet needed
- CLI/SDK "just works"
- **This is the only way to make it work**

#### ✅ Scenario 2: Cost Savings vs NAT Gateway
```
Before: EC2 → NAT Gateway ($32/month) → S3
After:  EC2 → S3 Interface Endpoint ($7.20/month)

Savings: ~$25/month + better security
```

#### ✅ Scenario 3: You Want "Zero Configuration" for Developers
```
Developer: aws s3 cp file.txt s3://bucket/
✅ Works immediately, no special configuration needed
```

---

## Cost Comparison

### Option 1: NAT Gateway (Current Common Setup)
```
NAT Gateway:         $32.40/month (730 hours × $0.045/hour)
Data transfer:       $0.045/GB processed
Total:               $32.40/month + data transfer
```

### Option 2: S3 Gateway Endpoint
```
Gateway endpoint:    FREE ✅
Data transfer:       FREE (same region) ✅
Requirement:         Must have NAT or IGW for DNS resolution
Total:               $0/month (but doesn't solve NAT dependency)
```

### Option 3: S3 Interface Endpoint (Replaces NAT for S3)
```
Interface endpoint:  $7.20/month per AZ
Data transfer:       FREE (same region) ✅
Total:               $7.20/month
Savings vs NAT:      ~$25/month + eliminates internet exposure
```

### Option 4: S3 Interface + Other Service Endpoints
```
S3 Interface:              $7.20/month
Secrets Manager Interface: $7.20/month
SSM (3 endpoints):         $21.60/month ($7.20 × 3)
Total:                     $36/month
vs NAT Gateway:            $32.40/month

⚠️ Slightly more expensive BUT:
✅ Better security (no internet exposure)
✅ Better reliability (no NAT single point of failure)
✅ Better compliance (fully private)
```

---

## Implementation in This Module

### Our Implementation: S3 **Gateway** Endpoint

**File:** `s3_bucket_endpoint.tf`

**Why we chose Gateway:**
- ✅ **FREE** (vs $7.20/month for Interface)
- ✅ Works with backup buckets when NAT exists
- ✅ Simple to implement (route table only)
- ⚠️ Assumes you have NAT Gateway OR you enable Interface separately

**How to enable:**
```terraform
module "mysql" {
  source = "./databases/ec2_mysql_arm"
  
  # Enable S3 Gateway Endpoint (FREE)
  enable_s3_endpoint = true
  
  # Note: If your EC2 is in fully private subnet without NAT,
  # this won't work for CLI/SDK access. Use Interface instead.
}
```

### Alternative: S3 **Interface** Endpoint (Not Implemented Yet)

**If you need fully private access without NAT:**

```terraform
# You would need to create this file: s3_interface_endpoint.tf

resource "aws_vpc_endpoint" "s3_interface" {
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [var.subnet_id]
  security_group_ids  = var.security_group_ids
  
  # CRITICAL: Must enable private DNS
  private_dns_enabled = true

  tags = {
    Name = "${var.env}-${var.project_id}-s3-interface-endpoint"
  }
}
```

**Cost:** $7.20/month, but enables fully private S3 access

---

## Troubleshooting

### Problem: `aws s3 ls s3://bucket` Hangs in Private Subnet

**Symptoms:**
- Command hangs indefinitely
- No error message
- Eventually times out

**Diagnosis:**
```bash
# Check DNS resolution
nslookup my-bucket.s3.eu-west-2.amazonaws.com

# If you see public IP (52.x.x.x):
# ❌ You have Gateway endpoint but no NAT/IGW
# ✅ You need Interface endpoint OR NAT Gateway
```

**Solution:**
```terraform
# Option 1: Add Interface Endpoint (fully private)
enable_s3_interface_endpoint = true  # Costs $7.20/month

# Option 2: Add NAT Gateway (less secure, more expensive)
# (not recommended if you want fully private architecture)
```

### Problem: Interface Endpoint Created But Still Hangs

**Diagnosis:**
```bash
# Check if private DNS is enabled
aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxxxx

# Look for: "PrivateDnsEnabled": true
```

**Solution:**
- Ensure `private_dns_enabled = true` in Terraform
- Verify security group allows outbound HTTPS (443)
- Wait 2-3 minutes for DNS propagation

### Problem: "Access Denied" with Endpoint Policy

**For Gateway Endpoints Only:**

If you restrict the endpoint policy to specific buckets:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject", "s3:PutObject"],
    "Resource": "arn:aws:s3:::my-backup-bucket/*"
  }]
}
```

You can only access `my-backup-bucket`. Other buckets will be denied.

**Note:** Interface endpoints do NOT support endpoint policies.

---

## Summary: The One-Liner Documentation

> **S3 Gateway endpoints do not require internet, but they also do not provide private DNS.**  
> **In private subnets without NAT, normal AWS CLI/SDK access to S3 requires an S3 Interface Endpoint.**

That's the exact truth. Everything else is just explaining *why*.

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────────┐
│  S3 VPC Endpoint Decision Tree                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Q: Do you have NAT Gateway or Internet Gateway?            │
│  ├─ YES → Use S3 Gateway (FREE)                             │
│  └─ NO  → Do you need CLI/SDK access to S3?                 │
│           ├─ YES → Use S3 Interface ($7.20/month)           │
│           └─ NO  → Use S3 Gateway (FREE, if just AWS        │
│                    managed services like Backup)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Additional Resources

- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [S3 Gateway Endpoint Pricing](https://aws.amazon.com/vpc/pricing/) (FREE)
- [S3 Interface Endpoint Pricing](https://aws.amazon.com/privatelink/pricing/) ($7.20/month/AZ)
- [Our Implementation: s3_bucket_endpoint.tf](../s3_bucket_endpoint.tf)

---

**Questions or Issues?**  
Check the [Troubleshooting](#troubleshooting) section or create an issue in the repository.

