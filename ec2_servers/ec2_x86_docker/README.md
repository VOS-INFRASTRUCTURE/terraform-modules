# EC2 Docker Server Module (x86_64/AMD64)

## Overview

This module deploys a production-ready EC2 instance with Docker pre-installed on x86_64/AMD64 architecture (Ubuntu 24.04). It includes comprehensive security features, CloudWatch monitoring, and automated EBS snapshots.

## Architecture

- **OS**: Ubuntu 24.04 LTS (x86_64/AMD64)
- **Docker**: Latest stable version installed and configured
- **Access**: AWS Systems Manager Session Manager (SSH-less) or SSH key
- **Monitoring**: CloudWatch Logs and Metrics
- **Backups**: Automated EBS snapshots via AWS Data Lifecycle Manager

## Features

- ✅ **Docker Pre-installed**: Latest Docker CE installed and ready to use
- ✅ **Secure Access**: Systems Manager Session Manager (no SSH keys needed)
- ✅ **IAM Roles**: Least-privilege IAM roles for secure AWS API access
- ✅ **Encrypted Storage**: EBS volumes encrypted at rest
- ✅ **CloudWatch Integration**: Comprehensive logging and metrics
- ✅ **Automated Snapshots**: EBS volume snapshots for disaster recovery
- ✅ **IMDSv2**: Instance Metadata Service v2 enforced for security
- ✅ **Cost Optimized**: Support for t3, t3a instance families

## Quick Start

### Basic Example (Development)

```hcl
module "docker_server" {
  source = "../../ec2_servers/ec2_x86_docker"

  env        = "development"
  project_id = "myapp"
  base_name  = "api-server"

  # Instance configuration
  subnet_id          = "subnet-12345678"
  security_group_ids = ["sg-app-servers"]

  # Use defaults: t3a.medium, 20GB storage, CloudWatch enabled
}
```

### Production Example (All Features)

```hcl
module "docker_prod_server" {
  source = "../../ec2_servers/ec2_x86_docker"

  env        = "production"
  project_id = "myapp"
  base_name  = "api-server"

  # Instance configuration
  instance_type = "t3a.large"  # 2 vCPU, 8 GB RAM
  subnet_id     = "subnet-private-1a"
  security_group_ids = ["sg-app-servers"]

  # Storage
  storage_size          = 50   # 50 GB
  storage_type          = "gp3"
  enable_ebs_encryption = true

  # Access
  enable_ssm_access     = true
  enable_ssh_key_access = false  # Use SSM only

  # Monitoring
  enable_cloudwatch_monitoring = true
  log_retention_days          = 30

  # Snapshots
  enable_ebs_snapshots        = true
  ebs_snapshot_interval_hours = 24
  ebs_snapshot_time           = "03:00"  # 3 AM UTC daily
  ebs_snapshot_retention_count = 14

  # Protection
  enable_termination_protection = true

  tags = {
    Environment = "production"
    Critical    = "true"
  }
}
```

## Variables

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `env` | Environment name (e.g., staging, production) | `string` |
| `project_id` | Project identifier | `string` |
| `subnet_id` | Subnet ID (private subnet recommended) | `string` |
| `security_group_ids` | List of security group IDs | `list(string)` |

### Optional Variables

| Name | Description | Default |
|------|-------------|---------|
| `base_name` | Base name for resources | `"mysql"` |
| `ami_id` | Ubuntu 24.04 AMI ID (auto-detected if not specified) | `"ami-05c172c7f0d3aed00"` |
| `instance_type` | EC2 instance type (t3, t3a families supported) | `"t3a.medium"` |
| `storage_size` | EBS volume size in GB | `20` |
| `storage_type` | EBS volume type (gp3 recommended) | `"gp3"` |
| `enable_ebs_encryption` | Encrypt EBS volumes | `true` |
| `enable_detailed_monitoring` | Detailed CloudWatch monitoring (1-min intervals) | `false` |
| `enable_termination_protection` | Prevent accidental instance termination | `false` |
| `key_name` | SSH key pair name (optional) | `""` |
| `enable_ssh_key_access` | Enable SSH key access | `false` |
| `enable_ssm_access` | Enable SSM Session Manager | `true` |
| `enable_cloudwatch_monitoring` | Enable CloudWatch logs and metrics | `true` |
| `log_retention_days` | CloudWatch log retention days | `7` |
| `enable_ebs_snapshots` | Enable automated EBS snapshots | `false` |
| `ebs_snapshot_interval_hours` | Hours between snapshots | `24` |
| `ebs_snapshot_time` | Daily snapshot time in UTC (HH:MM) | `"03:00"` |
| `ebs_snapshot_retention_count` | Number of snapshots to keep | `7` |
| `tags` | Additional resource tags | `{}` |

## Outputs

The module provides a single comprehensive output object:

```hcl
module.docker_server.mysql  # Output object containing all server details
```

### Output Structure

```json
{
  "instance": {
    "id": "i-0123456789abcdef",
    "arn": "arn:aws:ec2:...",
    "private_ip": "10.0.1.50",
    "public_ip": null,
    "availability_zone": "eu-west-2a",
    "instance_type": "t3a.medium"
  },
  "security": {
    "ebs_encrypted": true,
    "iam_role_arn": "arn:aws:iam::...",
    "iam_instance_profile": "...",
    "security_group_ids": ["sg-..."],
    "ssm_access_enabled": true,
    "ssh_key_access": false
  },
  "monitoring": {
    "enabled": true,
    "log_group_name": "/aws/ec2/...",
    "log_group_arn": "arn:aws:logs:...",
    "log_retention_days": 7
  },
  "backup": {
    "ebs_snapshots": {
      "enabled": true,
      "interval_hours": 24,
      "snapshot_time": "03:00",
      "retention_count": 7,
      "dlm_policy_id": "policy-...",
      "dlm_policy_arn": "arn:aws:dlm:..."
    }
  },
  "access": {
    "ssm_session_command": "aws ssm start-session --target i-...",
    "ssh_command": "SSH key access not configured"
  }
}
```

## Instance Type Options

### AMD (t3a series) - Best Value

| Instance Type | vCPU | RAM | Cost/Month* | Use Case |
|--------------|------|-----|-------------|----------|
| `t3a.micro` | 2 | 1 GB | ~$6 | Very light workloads |
| `t3a.small` | 2 | 2 GB | ~$12 | Light applications |
| `t3a.medium` | 2 | 4 GB | ~$24 | **Default** - General purpose |
| `t3a.large` | 2 | 8 GB | ~$48 | Memory-intensive apps |
| `t3a.xlarge` | 4 | 16 GB | ~$96 | High-performance apps |

### Intel (t3 series) - Slightly Higher Performance

| Instance Type | vCPU | RAM | Cost/Month* | Use Case |
|--------------|------|-----|-------------|----------|
| `t3.micro` | 2 | 1 GB | ~$7 | Very light workloads |
| `t3.small` | 2 | 2 GB | ~$14 | Light applications |
| `t3.medium` | 2 | 4 GB | ~$28 | General purpose |
| `t3.large` | 2 | 8 GB | ~$56 | Memory-intensive apps |
| `t3.xlarge` | 4 | 16 GB | ~$112 | High-performance apps |

*Approximate costs for eu-west-2 region (compute only, excludes storage)

**CPU Credits System:**

| Instance | Baseline Performance | Burst Performance | Credit Accrual Rate |
|----------|---------------------|-------------------|---------------------|
| t3a.micro | 10% | 100% | 12 credits/hour |
| t3a.small | 20% | 100% | 24 credits/hour |
| t3a.medium | 20% | 100% | 24 credits/hour |
| t3a.large | 30% | 100% | 36 credits/hour |

## Accessing the Server

### 1. SSM Session Manager (Recommended)

No SSH keys required, IAM-based access control:

```bash
# Get instance ID from Terraform output
INSTANCE_ID=$(terraform output -json docker_server | jq -r '.instance.id')

# Start SSM session
aws ssm start-session --target $INSTANCE_ID

# Once connected, Docker is ready to use
docker ps
docker run hello-world
```

### 2. SSH Access (Optional)

If `enable_ssh_key_access = true`:

```bash
# Get private IP
INSTANCE_IP=$(terraform output -json docker_server | jq -r '.instance.private_ip')

# Connect via SSH
ssh -i /path/to/key.pem ubuntu@$INSTANCE_IP
```

## Using Docker

Docker is pre-installed and ready to use:

```bash
# Connect to instance via SSM
aws ssm start-session --target i-0123456789abcdef

# Docker is ready (ubuntu user is in docker group)
docker version
docker info

# Run containers
docker run -d -p 80:80 nginx
docker run -d -p 3000:3000 node:18

# Docker Compose is also available
docker compose version
```

## Monitoring

### CloudWatch Logs

Available log streams (when `enable_cloudwatch_monitoring = true`):

```bash
# View setup logs
aws logs tail /aws/ec2/{project}-{env}-{base_name}/setup.log

# View system logs
aws logs tail /aws/ec2/{project}-{env}-{base_name}/syslog --follow

# View auth logs
aws logs tail /aws/ec2/{project}-{env}-{base_name}/auth.log

# View cloud-init logs
aws logs tail /aws/ec2/{project}-{env}-{base_name}/cloud-init.log
```

### CloudWatch Metrics

Automatically collected:
- **Memory Usage**: Percentage of memory used
- **Disk Usage**: Percentage of disk space used
- **CPU Utilization**: Available with detailed monitoring

### Create Alarms

```hcl
resource "aws_cloudwatch_metric_alarm" "high_memory" {
  alarm_name          = "${var.project_id}-${var.env}-high-memory"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUsed"
  namespace           = "EC2/"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  
  dimensions = {
    InstanceId = module.docker_server.mysql.instance.id
  }
}
```

## Backups (EBS Snapshots)

### How It Works

When `enable_ebs_snapshots = true`:

- **Technology**: AWS Data Lifecycle Manager (DLM) - fully managed by AWS
- **Schedule**: Daily at 3 AM UTC by default (configurable)
- **Retention**: Last 7 snapshots kept automatically (configurable)
- **Incremental**: Only changed blocks stored (cost-efficient)
- **Tags**: Snapshots auto-tagged for easy identification

### Configuration Examples

**Development:**
```hcl
enable_ebs_snapshots         = false  # No snapshots needed
```

**Production:**
```hcl
enable_ebs_snapshots        = true
ebs_snapshot_interval_hours = 24       # Daily
ebs_snapshot_time           = "03:00"  # 3 AM UTC
ebs_snapshot_retention_count = 14      # Keep 2 weeks
```

### List Snapshots

```bash
# List all snapshots for this server
aws ec2 describe-snapshots \
  --filters "Name=tag:Name,Values=*{project}*{env}*" \
  --query 'Snapshots[*].[SnapshotId,StartTime,VolumeSize,Description]' \
  --output table
```

### Restore from Snapshot

**Option 1: Create new volume from snapshot**
```bash
# Get latest snapshot ID
SNAPSHOT_ID=$(aws ec2 describe-snapshots \
  --filters "Name=tag:Name,Values=*your-server*" \
  --query 'Snapshots | sort_by(@, &StartTime) | [-1].SnapshotId' \
  --output text)

# Create volume from snapshot
aws ec2 create-volume \
  --snapshot-id $SNAPSHOT_ID \
  --availability-zone eu-west-2a \
  --volume-type gp3

# Attach to instance or launch new instance with this volume
```

**Option 2: Launch new instance from snapshot**
```bash
# Create AMI from snapshot
aws ec2 create-image \
  --instance-id i-ORIGINAL-INSTANCE-ID \
  --name "server-backup-$(date +%Y%m%d)" \
  --description "Server backup from snapshot"

# Update Terraform with new AMI ID to launch new instance
```

## Security Features

### 1. Encrypted Storage
- EBS volumes encrypted at rest using AWS managed keys
- Enabled by default (`enable_ebs_encryption = true`)

### 2. IAM Roles (Least Privilege)
The EC2 instance has minimal permissions:
- ✅ CloudWatch Logs write access
- ✅ SSM Session Manager access
- ❌ Cannot create/modify other AWS resources

### 3. IMDSv2 Enforced
- Instance Metadata Service v2 required
- Prevents SSRF attacks
- Session-based access to instance metadata

### 4. SSH-less Access
- SSM Session Manager recommended (no SSH keys to manage)
- IAM-based access control
- All sessions logged in CloudTrail

### 5. Private Subnet Deployment
- Recommended to deploy in private subnets
- No direct internet access
- Access via NAT Gateway or VPC endpoints

## Troubleshooting

### Issue: Can't connect via SSM

**Check SSM agent status:**
```bash
# SSM agent is pre-installed on Ubuntu 24.04
# If issues occur, check IAM role and VPC endpoints

# Verify instance has SSM role attached
aws ec2 describe-instances --instance-ids i-xxx \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Check VPC endpoints (if in private subnet without NAT)
# Required endpoints: ssm, ssmmessages, ec2messages
```

### Issue: Docker commands fail

**Check Docker installation:**
```bash
# Connect to instance
aws ssm start-session --target i-xxx

# Check Docker status
sudo systemctl status docker

# Restart Docker if needed
sudo systemctl restart docker

# Verify user is in docker group
groups ubuntu
```

### Issue: High disk usage

**Check disk space:**
```bash
df -h

# Clean up Docker
docker system df
docker system prune -a --volumes  # Remove unused containers/images/volumes
```

## Cost Estimation

| Component | Configuration | Monthly Cost (eu-west-2) |
|-----------|--------------|-------------------------|
| **Compute** | t3a.medium (2 vCPU, 4 GB) | ~$24.00 |
| **Storage** | 20 GB gp3 | ~$1.60 |
| **Snapshots** | 7 snapshots × 20 GB | ~$3.50 |
| **CloudWatch Logs** | ~1 GB/month | ~$0.50 |
| **Data Transfer** | Minimal internal | ~$0.00 |
| **Total** | | **~$29.60/month** |

**Tips to reduce costs:**
- Use t3a instead of t3 (10% cheaper)
- Reduce log retention from 30 to 7 days
- Disable detailed monitoring if not needed
- Use smaller instance for non-production
- Clean up unused Docker images regularly

## Security Checklist

Before deploying to production:

- [ ] Deploy in private subnet
- [ ] Enable EBS encryption
- [ ] Enable CloudWatch monitoring
- [ ] Enable EBS snapshots
- [ ] Use SSM Session Manager (disable SSH)
- [ ] Restrict security group to minimum required ports
- [ ] Enable termination protection
- [ ] Set up CloudWatch alarms
- [ ] Test snapshot restore procedure
- [ ] Review IAM policies
- [ ] Configure VPC endpoints (if no NAT Gateway)

## Related Documentation

- [Session Manager Guide](./documentations/SessionManager.md)
- [CloudWatch Logs](./documentations/CLOUDWATCH_LOGS.md)
- [Snapshots Overview](./documentations/SNAPSHOTS.md)
- [AWS Systems Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)

---

**Module ready for production use with Docker pre-installed!** 🐳

