# AWS Session Manager VPC Endpoints Module

Production-ready Terraform module for creating AWS Systems Manager Session Manager VPC Interface Endpoints. Enables SSH-less access to EC2 instances in private subnets **without requiring NAT Gateway or Internet Gateway**.

## 🎯 Overview

This module creates the three mandatory VPC Interface Endpoints required for AWS Session Manager to work in private subnets:

1. **com.amazonaws.{region}.ssm** - Systems Manager API
2. **com.amazonaws.{region}.ssmmessages** - Session Manager messaging
3. **com.amazonaws.{region}.ec2messages** - EC2 instance communication

### Why Use This Module?

| Feature | Benefit |
|---------|---------|
| ✅ **No SSH Keys** | Eliminates SSH key management and rotation |
| ✅ **No NAT Gateway** | Saves ~$10/month compared to NAT Gateway |
| ✅ **No Public IPs** | EC2 instances stay fully private |
| ✅ **No Open Ports** | No need for port 22 (SSH) in security groups |
| ✅ **Audit Trail** | All access logged in CloudTrail |
| ✅ **IAM-Based Access** | Fine-grained access control via IAM policies |
| ✅ **No Internet Access** | All traffic stays within AWS network |

## 💰 Cost Comparison

### Monthly Cost Breakdown

| Solution | Base Cost | Data Transfer | Total Est. |
|----------|-----------|---------------|------------|
| **NAT Gateway** | $32.40 | $0.045/GB | ~$35-50/month |
| **Session Manager Endpoints** (this module) | $21.60 | $0.01/GB | ~$22-25/month |
| **Savings** | -$10.80 | ~70% cheaper | **~$10-25/month** |

> **Note:** Costs are for single AZ deployment. Multi-AZ deployments multiply endpoint costs by number of AZs.

### Cost Formula
```
Interface Endpoint Cost = $0.01/hour × 24 hours × 30 days = $7.20/month per endpoint
Total Cost = 3 endpoints × $7.20 = $21.60/month (single AZ)
```

## 🏗️ Architecture

### Network Topology

```
┌─────────────────────────────────────────────────────────────────────┐
│                         AWS Region (eu-west-2)                       │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    VPC (10.0.0.0/16)                          │  │
│  │                                                                │  │
│  │  ┌────────────────────────────────────────────────────────┐  │  │
│  │  │         Private Subnet (10.0.1.0/24)                    │  │  │
│  │  │                                                          │  │  │
│  │  │  ┌──────────────┐         ┌──────────────────────────┐ │  │  │
│  │  │  │ EC2 Instance │────────▶│ VPC Endpoint ENI         │ │  │  │
│  │  │  │ (Private IP) │  HTTPS  │ (Private IP: 10.0.1.100) │ │  │  │
│  │  │  │              │   443   │                          │ │  │  │
│  │  │  │ • SSM Agent  │         │ • ssm endpoint           │ │  │  │
│  │  │  │ • IAM Role   │         │ • ssmmessages endpoint   │ │  │  │
│  │  │  └──────────────┘         │ • ec2messages endpoint   │ │  │  │
│  │  │                           └──────────────────────────┘ │  │  │
│  │  │                                      │                  │  │  │
│  │  └──────────────────────────────────────┼──────────────────┘  │  │
│  │                                         │                     │  │
│  └─────────────────────────────────────────┼─────────────────────┘  │
│                                            │                         │
│                                            │                         │
│                    ┌───────────────────────┼────────────────────┐   │
│                    │   AWS PrivateLink Network (Internal AWS)   │   │
│                    └───────────────────────┼────────────────────┘   │
│                                            │                         │
└────────────────────────────────────────────┼─────────────────────────┘
                                             │
                                             ▼
                              ┌────────────────────────────┐
                              │ AWS Systems Manager Service │
                              │    (Managed by AWS)         │
                              └────────────────────────────┘
                                             ▲
                                             │
                                    ┌────────┴─────────┐
                                    │                  │
                              ┌─────▼─────┐      ┌────▼─────┐
                              │ AWS CLI   │      │  AWS     │
                              │ (User PC) │      │ Console  │
                              └───────────┘      └──────────┘
```

### Traffic Flow

1. **User initiates connection** via AWS Console or CLI:
   ```bash
   aws ssm start-session --target i-0123456789abcdef0
   ```

2. **Request flows**:
   - User → AWS API (over internet) → Session Manager Service
   - Session Manager Service → VPC Endpoint (ssm) → EC2 Instance

3. **Session established**:
   - EC2 Instance ↔ ssmmessages endpoint (bidirectional messaging)
   - EC2 Instance → ec2messages endpoint (status updates)

4. **All traffic stays private** - no NAT, no IGW, no public IPs needed!

## 📋 Prerequisites

### EC2 Instance Requirements

| Requirement | Details |
|-------------|---------|
| **SSM Agent** | Pre-installed on Amazon Linux 2, Ubuntu 20.04+, Windows Server 2016+ |
| **IAM Role** | Must have `AmazonSSMManagedInstanceCore` policy attached |
| **Security Group** | Must allow outbound HTTPS (443) to VPC CIDR or endpoint security group |
| **Network** | Can be in private subnet (no public IP needed) |

### IAM Role for EC2 Instance

```hcl
# Attach this managed policy to your EC2 instance role
data "aws_iam_policy" "ssm_managed_instance_core" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = data.aws_iam_policy.ssm_managed_instance_core.arn
}
```

### EC2 Security Group

```hcl
# Your EC2 security group must allow outbound HTTPS
resource "aws_security_group" "ec2" {
  # ... other configuration ...

  egress {
    description = "Allow outbound HTTPS for Session Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Your VPC CIDR
  }
}
```

## 🚀 Usage

### Minimal Example

```hcl
module "session_manager_endpoints" {
  source = "../../vpc_endpoints/session_manager_endpoint"

  # Required variables
  env        = "production"
  project_id = "myapp"

  # Network configuration
  subnet_ids = ["subnet-abc123", "subnet-def456"] # Private subnets

  # Security groups of EC2 instances that need Session Manager access
  resources_security_group_ids = ["sg-ec2instance123"]

  # Enable endpoints (default: false to avoid costs)
  enable_session_manager_endpoints = true
}
```

### Multi-Subnet High Availability

```hcl
module "session_manager_endpoints" {
  source = "../../vpc_endpoints/session_manager_endpoint"

  env        = "production"
  project_id = "backend-api"

  # Multiple subnets for HA (different AZs)
  subnet_ids = [
    "subnet-private-a", # eu-west-2a
    "subnet-private-b", # eu-west-2b
  ]

  # Multiple EC2 security groups
  resources_security_group_ids = [
    "sg-web-servers",
    "sg-app-servers",
    "sg-database-instances",
  ]

  enable_session_manager_endpoints = true
}
```

### Cost-Optimized (Single Subnet)

```hcl
module "session_manager_endpoints" {
  source = "../../vpc_endpoints/session_manager_endpoint"

  env        = "staging"
  project_id = "myapp"

  # Single subnet for cost optimization
  subnet_ids = ["subnet-private-a"]

  resources_security_group_ids = ["sg-staging-instances"]

  enable_session_manager_endpoints = true
}

# Cost: ~$21.60/month (single AZ)
# vs Multi-AZ: ~$43.20/month (2 AZs)
```

### Disable Endpoints (Use NAT Gateway Instead)

```hcl
module "session_manager_endpoints" {
  source = "../../vpc_endpoints/session_manager_endpoint"

  env        = "dev"
  project_id = "myapp"

  subnet_ids                   = ["subnet-private-a"]
  resources_security_group_ids = ["sg-dev-instances"]

  # Disabled - EC2 instances will use NAT Gateway or public internet
  enable_session_manager_endpoints = false
}

# Cost: $0 (endpoints not created)
# Note: Requires NAT Gateway (~$32.40/month) or IGW for Session Manager
```

## 📊 Module Inputs

### Required Variables

| Variable | Type | Description |
|----------|------|-------------|
| `env` | `string` | Environment name (e.g., 'production', 'staging', 'dev') |
| `project_id` | `string` | Project identifier for resource tagging |
| `subnet_ids` | `list(string)` | List of subnet IDs where endpoints will be created |
| `resources_security_group_ids` | `list(string)` | Security group IDs of EC2 instances needing access |

### Optional Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_session_manager_endpoints` | `bool` | `false` | Enable/disable endpoint creation |

## 📤 Module Outputs

### Output Structure

```hcl
output "session_manager_endpoints" {
  value = {
    enabled = true

    # Individual endpoint details
    ssm = {
      endpoint_id         = "vpce-0123456789abcdef0"
      endpoint_arn        = "arn:aws:ec2:eu-west-2:..."
      service_name        = "com.amazonaws.eu-west-2.ssm"
      private_dns_enabled = true
      dns_entries         = []
    }

    ssmmessages = {  }
    ec2messages = {  }

    # Network configuration
    network = {
      vpc_id             = "vpc-abc123"
      subnet_ids         = ["subnet-abc123"]
      security_group_ids = ["sg-endpoints123"]
      vpc_cidr_block     = "10.0.0.0/16"
    }

    # Cost information
    cost = {
      monthly_estimate = "~$21.60 USD"
      comparison       = "NAT Gateway: ~$32.40/month"
      savings          = "~$10.80/month"
    }

    # Usage instructions
    usage = {
      connect_command = "aws ssm start-session --target <instance-id>"
      requirements    = [...]
    }
  }
}
```

### Accessing Outputs

```hcl
# Get endpoint IDs
output "ssm_endpoint_id" {
  value = module.session_manager_endpoints.session_manager_endpoints.ssm.endpoint_id
}

# Get cost estimate
output "monthly_cost" {
  value = module.session_manager_endpoints.session_manager_endpoints.cost.monthly_estimate
}
```

## 🔧 How to Connect

### Method 1: AWS Console

1. Go to **EC2 Console** → **Instances**
2. Select your instance
3. Click **Connect** → **Session Manager** tab
4. Click **Connect**

### Method 2: AWS CLI

```bash
# Start interactive session
aws ssm start-session --target i-0123456789abcdef0

# Run command without interactive session
aws ssm send-command \
  --instance-ids "i-0123456789abcdef0" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["uptime"]'

# Port forwarding (access private RDS from local machine)
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["3306"],"localPortNumber":["3306"]}'
```

### Method 3: AWS Systems Manager Fleet Manager

1. Go to **Systems Manager** → **Fleet Manager**
2. Select your instance
3. Click **Node actions** → **Start terminal session**

## 🔍 Verification

### Check Endpoint Status

```bash
# Verify endpoints are created
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-abc123" \
  --query 'VpcEndpoints[?ServiceName==`com.amazonaws.eu-west-2.ssm`]'
```

### Test from EC2 Instance

```bash
# Connect via Session Manager
aws ssm start-session --target i-0123456789abcdef0

# Once connected, verify private DNS resolution
nslookup ssm.eu-west-2.amazonaws.com
# Should resolve to private IP (10.x.x.x)

# Check SSM Agent status
sudo systemctl status amazon-ssm-agent

# Verify connectivity
curl -I https://ssm.eu-west-2.amazonaws.com
```

## 🐛 Troubleshooting

### Issue: "Instance not available for Session Manager"

**Possible causes:**

1. **Missing IAM role** - EC2 must have `AmazonSSMManagedInstanceCore` policy
   ```bash
   # Check instance IAM role
   aws ec2 describe-instances --instance-ids i-xxx --query 'Reservations[0].Instances[0].IamInstanceProfile'
   ```

2. **SSM Agent not running**
   ```bash
   # Connect via AWS Console (EC2 Instance Connect or SSH if available)
   sudo systemctl status amazon-ssm-agent
   sudo systemctl start amazon-ssm-agent
   ```

3. **Security group blocks outbound 443**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups --group-ids sg-xxx
   ```

4. **Endpoints not created or unhealthy**
   ```bash
   # Check endpoint status
   aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxx
   ```

### Issue: "Connection timeout"

**Possible causes:**

1. **Private DNS not enabled** - Must be `true` on all three endpoints
2. **Endpoint security group blocks inbound 443** - Check `security_groups.tf`
3. **Subnet route table incorrect** - Should NOT route to NAT/IGW for endpoint traffic

### Issue: "Access denied"

**Possible causes:**

1. **IAM user lacks permissions**
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "ssm:StartSession",
       "ssm:TerminateSession",
       "ssm:ResumeSession",
       "ssm:DescribeSessions",
       "ssm:GetConnectionStatus"
     ],
     "Resource": "*"
   }
   ```

2. **Session Manager preferences restrict access** - Check Systems Manager → Session Manager → Preferences

### Issue: "High costs"

**Solution:** Use single-subnet deployment for non-production environments

```hcl
# Production: Multi-AZ for HA (~$43/month)
subnet_ids = ["subnet-a", "subnet-b"]

# Staging/Dev: Single AZ for cost savings (~$21/month)
subnet_ids = ["subnet-a"]
```

## ⚠️ Important Notes

### Critical Requirements

1. **ALL THREE endpoints are mandatory** - Missing even one breaks Session Manager
2. **Private DNS must be enabled** - Set to `true` on all endpoints
3. **EC2 IAM role required** - Must have `AmazonSSMManagedInstanceCore` policy
4. **Security groups must allow HTTPS (443)** - Both EC2 and endpoint security groups

### Security Best Practices

- ✅ Use separate security group for endpoints (this module does this automatically)
- ✅ Restrict endpoint egress to VPC CIDR only (not 0.0.0.0/0)
- ✅ Use IAM policies to restrict which users can access which instances
- ✅ Enable Session Manager logging to S3 or CloudWatch for audit trail
- ✅ Use session document for command restrictions (prevent sudo, shell access, etc.)

### Cost Optimization

- Use single subnet for dev/staging environments
- Use multi-subnet for production (HA)
- Consider NAT Gateway if you need internet access anyway (no cost benefit from endpoints)
- Monitor data transfer costs (usually negligible for Session Manager)

## 📚 Additional Resources

- [AWS Session Manager Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [Session Manager IAM Policies](https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-create-iam-instance-profile.html)
- [Troubleshooting Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-troubleshooting.html)

## 🔐 Security Considerations

### Network Isolation

- All traffic stays within AWS network (never touches internet)
- No NAT Gateway or Internet Gateway required
- EC2 instances can remain in fully isolated private subnets

### Access Control

- IAM-based authentication (no SSH keys to manage)
- Fine-grained permissions per user/role
- Integration with AWS Organizations for cross-account access
- MFA can be enforced via IAM policies

### Audit & Compliance

- All sessions logged to CloudTrail
- Optional session logging to S3 or CloudWatch
- Session recording for compliance
- Integration with AWS Config for compliance checks

## 📝 License

This module is part of the internal Terraform modules library.

## 🤝 Support

For issues or questions:
1. Check the troubleshooting section above
2. Review AWS Session Manager documentation
3. Contact DevOps team

---

**Last Updated:** January 28, 2026  
**Module Version:** 1.0.0  
**Tested with:** Terraform 1.5+, AWS Provider 5.0+

