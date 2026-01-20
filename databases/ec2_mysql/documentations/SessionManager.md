# AWS Systems Manager Session Manager - Complete Guide

## Overview

**AWS Systems Manager Session Manager** is a fully managed service that lets you connect to EC2 instances through a browser-based shell or AWS CLI **without requiring SSH, bastion hosts, or open inbound ports**.

Session Manager provides secure, auditable instance management with:
- ✅ **No SSH required** - No port 22, no SSH keys, no bastion hosts
- ✅ **No inbound rules** - Zero inbound security group rules needed
- ✅ **IAM-based access** - Integrate with AWS IAM and MFA
- ✅ **Full audit logging** - All sessions logged to CloudWatch/S3
- ✅ **Works in private subnets** - No public IP needed

---

## Table of Contents

1. [How Session Manager Works](#how-session-manager-works)
2. [Architecture](#architecture)
3. [Requirements](#requirements)
4. [Network Connectivity](#network-connectivity)
5. [Security Comparison: SSH vs Session Manager](#security-comparison)
6. [Setup Examples](#setup-examples)
7. [Common Use Cases](#common-use-cases)
8. [Troubleshooting](#troubleshooting)

---

## How Session Manager Works

### Connection Flow

```
┌──────────────────┐
│   Your Laptop    │
│  (AWS Console/   │
│    AWS CLI)      │
└────────┬─────────┘
         │
         │ 1. Request session via IAM
         ▼
┌─────────────────────────────────┐
│  AWS Systems Manager Service    │
│  (Validates IAM permissions)    │
└────────┬────────────────────────┘
         │
         │ 2. Authorize & establish session
         ▼
┌─────────────────────────────────┐
│      EC2 Instance               │
│  ┌──────────────────────────┐   │
│  │    SSM Agent             │   │
│  │  (Outbound HTTPS 443)    │◄──┼── 3. Agent polls for commands
│  └──────────────────────────┘   │
│                                 │
│  ┌──────────────────────────┐   │
│  │  Your Application        │   │
│  │  (MySQL, Redis, etc.)    │   │
│  └──────────────────────────┘   │
└─────────────────────────────────┘
```

### Key Characteristics

| Aspect | Detail |
|--------|--------|
| **Connection Direction** | **Outbound only** from EC2 instance |
| **Protocol** | HTTPS (TCP 443) |
| **Authentication** | AWS IAM credentials + instance profile |
| **Session Tracking** | CloudWatch Logs, S3, or both |
| **Encryption** | TLS 1.2+ (in-transit encryption) |

**Important**: The EC2 instance **initiates** the connection to AWS. AWS never opens a connection into your instance. This is why no inbound rules are needed.

---

## Architecture

### Scenario 1: Private Subnet with NAT Gateway (Common)

```
┌────────────────────────────────────────────────────────────┐
│                         VPC                                │
│                                                            │
│  ┌──────────────────────┐      ┌─────────────────────┐   │
│  │   Private Subnet     │      │   Public Subnet     │   │
│  │                      │      │                     │   │
│  │  ┌───────────────┐   │      │  ┌──────────────┐  │   │
│  │  │ EC2 Instance  │   │      │  │ NAT Gateway  │  │   │
│  │  │ (MySQL)       │   │      │  └──────┬───────┘  │   │
│  │  │               │   │      │         │          │   │
│  │  │ SSM Agent     │   │      │         │          │   │
│  │  └───────┬───────┘   │      │         │          │   │
│  │          │           │      │         │          │   │
│  │          │ Outbound  │      │         │          │   │
│  │          │ 443       │      │         │          │   │
│  │          └───────────┼──────┼─────────┘          │   │
│  │                      │      │         │          │   │
│  └──────────────────────┘      └─────────┼──────────┘   │
│                                           │              │
└───────────────────────────────────────────┼──────────────┘
                                            │
                                            ▼
                                   Internet Gateway
                                            │
                                            ▼
                              AWS Systems Manager Endpoints
                              - ssm.region.amazonaws.com
                              - ssmmessages.region.amazonaws.com
                              - ec2messages.region.amazonaws.com
```

**Security Group Configuration:**
- **Inbound**: None (❌ No rules)
- **Outbound**: TCP 443 → 0.0.0.0/0

---

### Scenario 2: Fully Private with VPC Endpoints (Best Practice)

```
┌────────────────────────────────────────────────────────────┐
│                         VPC                                │
│                                                            │
│  ┌──────────────────────┐      ┌─────────────────────┐   │
│  │   Private Subnet     │      │  VPC Endpoints      │   │
│  │                      │      │  (PrivateLink)      │   │
│  │  ┌───────────────┐   │      │                     │   │
│  │  │ EC2 Instance  │   │      │  • ssm              │   │
│  │  │ (MySQL)       │   │      │  • ssmmessages      │   │
│  │  │               │   │      │  • ec2messages      │   │
│  │  │ SSM Agent     │───┼──────┼─►                   │   │
│  │  └───────────────┘   │      │  (Port 443)         │   │
│  │                      │      │                     │   │
│  │  No public IP        │      │                     │   │
│  │  No internet access  │      │                     │   │
│  └──────────────────────┘      └─────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
                    ▲
                    │
              All traffic stays
              within AWS network
              (No internet needed)
```

**Security Group Configuration:**
- **Inbound**: None (❌ No rules)
- **Outbound**: TCP 443 → VPC Endpoint Security Group

**Benefits:**
- ✅ No internet access required
- ✅ Lower data transfer costs
- ✅ Better security (traffic never leaves AWS)
- ✅ Faster connections

---

## Requirements

### ✅ What Session Manager REQUIRES

| Component | Requirement | Details |
|-----------|-------------|---------|
| **SSM Agent** | Installed & Running | Pre-installed on Amazon Linux 2/2023, Ubuntu 20.04+, most AWS AMIs |
| **IAM Instance Profile** | Attached to EC2 | Must have `AmazonSSMManagedInstanceCore` policy |
| **Outbound Connectivity** | TCP 443 | To SSM endpoints (via internet or VPC endpoints) |
| **IAM User/Role** | With SSM Permissions | User running `aws ssm start-session` needs permissions |

### ❌ What Session Manager DOES NOT REQUIRE

| Component | Status | Why Not Needed |
|-----------|--------|----------------|
| **SSH (Port 22)** | ❌ Not required | Session Manager uses HTTPS (443) |
| **Inbound Security Rules** | ❌ Not required | Connection is outbound from instance |
| **Public IP Address** | ❌ Not required | Works in private subnets |
| **Bastion Host** | ❌ Not required | Direct connection via AWS |
| **SSH Key Pairs** | ❌ Not required | Uses IAM authentication |
| **VPN** | ❌ Not required | Connection via AWS API |

---

## Network Connectivity

### Required AWS Endpoints

The EC2 instance must reach these endpoints over **HTTPS (443)**:

| Endpoint | Purpose | Example |
|----------|---------|---------|
| **ssm** | Systems Manager API | `ssm.eu-west-2.amazonaws.com` |
| **ssmmessages** | Session data transfer | `ssmmessages.eu-west-2.amazonaws.com` |
| **ec2messages** | Command polling | `ec2messages.eu-west-2.amazonaws.com` |

### Connectivity Options

#### Option 1: Internet Access via NAT Gateway/Instance
```hcl
# Security Group (minimal)
resource "aws_security_group" "mysql_ssm_only" {
  name = "mysql-ssm-only"
  vpc_id = var.vpc_id

  # No inbound rules

  egress {
    description = "HTTPS to AWS SSM endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Pros:**
- ✅ Simple setup
- ✅ No VPC endpoint costs

**Cons:**
- ❌ NAT Gateway costs (~$32/month)
- ❌ Traffic leaves AWS network
- ❌ Data transfer charges

---

#### Option 2: VPC Endpoints (Recommended for Production)
```hcl
# VPC Endpoints for fully private connectivity
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type = "Interface"
  subnet_ids        = var.private_subnet_ids
  security_group_ids = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true
}

# Security group for VPC endpoints
resource "aws_security_group" "vpc_endpoints" {
  name   = "ssm-vpc-endpoints"
  vpc_id = var.vpc_id

  ingress {
    description = "HTTPS from EC2 instances"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
}
```

**Pros:**
- ✅ No internet access needed
- ✅ No NAT Gateway costs
- ✅ Traffic stays in AWS
- ✅ Better security
- ✅ Lower latency

**Cons:**
- ❌ VPC endpoint costs (~$7/month per endpoint × 3 = $21/month)

---

## Security Comparison

### SSH vs Session Manager

| Feature | SSH | Session Manager |
|---------|-----|-----------------|
| **Inbound Port Required** | Yes (22) | ❌ No |
| **Security Group Rules** | Inbound 22 from specific IPs | ❌ No inbound rules |
| **Public IP/Bastion** | Required (or VPN) | ❌ Not required |
| **Authentication** | SSH keys | AWS IAM |
| **MFA Support** | Manual setup | ✅ Native IAM MFA |
| **Access Control** | Manual key management | ✅ IAM policies |
| **Session Logging** | Manual (rsyslog) | ✅ CloudWatch/S3 automatic |
| **Audit Trail** | Limited | ✅ Complete (who, when, what) |
| **Key Rotation** | Manual | ❌ N/A (no keys) |
| **Works in Private Subnet** | Only with VPN/bastion | ✅ Yes (via VPC endpoints) |
| **Port Scanning Risk** | Yes (port 22 exposed) | ❌ No exposed ports |
| **Brute Force Attacks** | Possible | ❌ Not applicable |
| **Compliance** | Manual audit | ✅ Built-in compliance logging |

---

## Setup Examples

### Example 1: Basic Session Manager Setup

This is already configured in the `ec2_mysql` module:

```hcl
module "mysql_db" {
  source = "../../databases/ec2_mysql"

  env        = "production"
  project_id = "myapp"
  
  # Instance config
  ami_id     = "ami-0c55b159cbfafe1f0"
  subnet_id  = "subnet-private-1a"
  
  # Session Manager enabled by default
  enable_ssm_access = true  # ✅ Enabled
  
  # SSH disabled (recommended)
  enable_ssh_key_access = false  # ❌ No SSH
  key_name              = ""
}
```

The module automatically:
- ✅ Creates IAM role with `AmazonSSMManagedInstanceCore`
- ✅ Attaches instance profile to EC2
- ✅ SSM Agent is pre-installed on Ubuntu 24.04
- ✅ No inbound security group rules

---

### Example 2: Connect to Instance

#### Via AWS Console:
1. Go to **EC2 Console** → **Instances**
2. Select your instance
3. Click **Connect** → **Session Manager** tab
4. Click **Connect**

#### Via AWS CLI:
```bash
# Start session
aws ssm start-session --target i-0123456789abcdef

# Execute single command
aws ssm send-command \
  --instance-ids i-0123456789abcdef \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["docker ps"]

# Port forwarding (access MySQL locally)
aws ssm start-session \
  --target i-0123456789abcdef \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=3306,localPortNumber=3306
```

#### Common Session Manager Commands:

```bash
# Check SSM agent status
aws ssm describe-instance-information \
  --filters "Key=tag:Name,Values=production-mysql"

# View active sessions
aws ssm describe-sessions --state Active

# Terminate session
aws ssm terminate-session --session-id <session-id>
```

---

## Common Use Cases

### 1. **Database Server Access** (Like MySQL Module)

**Scenario**: Connect to MySQL server in private subnet

```bash
# Connect to instance
aws ssm start-session --target i-mysql-instance

# Once connected, access MySQL
docker exec -it mysql-server mysql -u root -p
```

**Security:**
- ❌ No port 3306 exposed to internet
- ❌ No port 22 exposed
- ✅ Full audit trail of who accessed when

---

### 2. **Port Forwarding** (Access MySQL from Local Machine)

```bash
# Forward MySQL port to localhost
aws ssm start-session \
  --target i-mysql-instance \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3306"],"localPortNumber":["3306"]}'

# Now connect locally
mysql -h 127.0.0.1 -P 3306 -u myuser -p
```

---

### 3. **File Transfer**

```bash
# Upload file to instance
aws ssm send-command \
  --instance-ids i-mysql-instance \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["aws s3 cp s3://my-bucket/backup.sql /tmp/"]'

# Or use SCP-like functionality
aws ssm start-session \
  --target i-mysql-instance \
  --document-name AWS-StartNonInteractiveCommand \
  --parameters command="cat > /tmp/myfile.txt"
```

---

### 4. **Run Commands Without Shell**

```bash
# Check disk usage
aws ssm send-command \
  --instance-ids i-mysql-instance \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["df -h"]

# Check MySQL status
aws ssm send-command \
  --instance-ids i-mysql-instance \
  --document-name "AWS-RunShellScript" \
  --parameters commands=["docker ps | grep mysql"]
```

---

## Troubleshooting

### Issue: Instance Not Showing in Session Manager

**Symptoms:**
- Instance doesn't appear in Systems Manager → Fleet Manager
- "Cannot connect" error when trying to start session

**Diagnosis:**
```bash
# Check if instance is registered
aws ssm describe-instance-information

# Check SSM agent status (on instance via console)
systemctl status amazon-ssm-agent

# Check IAM instance profile
aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[].Instances[].IamInstanceProfile'
```

**Common Causes & Fixes:**

| Cause | Fix |
|-------|-----|
| SSM Agent not running | `sudo systemctl start amazon-ssm-agent` |
| No IAM instance profile | Attach role with `AmazonSSMManagedInstanceCore` |
| No outbound 443 access | Add security group egress rule for 443 |
| VPC endpoints misconfigured | Verify endpoints exist and security groups allow 443 |
| Wrong region | Ensure using correct region for endpoints |

---

### Issue: "User is not authorized to perform: ssm:StartSession"

**Cause:** IAM user/role lacks Session Manager permissions

**Fix:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:StartSession"
      ],
      "Resource": [
        "arn:aws:ec2:*:*:instance/*"
      ],
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "eu-west-2"
        }
      }
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:TerminateSession",
        "ssm:ResumeSession"
      ],
      "Resource": [
        "arn:aws:ssm:*:*:session/${aws:username}-*"
      ]
    }
  ]
}
```

---

### Issue: Connection Slow or Timing Out

**Possible Causes:**
1. High latency to SSM endpoints
2. NAT Gateway congestion
3. Instance under heavy load

**Solutions:**
- Use VPC endpoints (lower latency)
- Check instance CPU/memory usage
- Verify network ACLs aren't blocking 443

---

## Summary: Session Manager at a Glance

### What You Need

✅ **Outbound HTTPS (443)** - To SSM endpoints  
✅ **SSM Agent** - Running on instance  
✅ **IAM Instance Profile** - With SSM permissions  
✅ **IAM User Permissions** - To start sessions  

### What You DON'T Need

❌ **No SSH (port 22)**  
❌ **No inbound security group rules**  
❌ **No public IP**  
❌ **No bastion host**  
❌ **No SSH keys**  

### Key Benefits

🔒 **Zero inbound ports** - Eliminates attack surface  
🔑 **IAM-based access** - Centralized authentication  
📋 **Complete audit trail** - CloudWatch/S3 logging  
🏢 **Compliance-ready** - Built-in session recording  
💰 **Cost-effective** - No bastion hosts to maintain  

---

## Related Documentation

- [AWS Session Manager Official Docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [IAM Policies for Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-iam-instance-profile.html)
- [VPC Endpoints for Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [Session Manager Logging](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging.html)

---

**Last Updated:** January 2026

