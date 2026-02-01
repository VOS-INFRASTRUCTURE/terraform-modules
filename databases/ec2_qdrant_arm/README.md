# EC2 Qdrant ARM Module

Deploy Qdrant vector database natively on EC2 ARM (Graviton) instances for maximum performance and cost efficiency.

## Features

- **Native Installation**: Qdrant runs natively on Ubuntu 24.04 ARM64 (no Docker overhead)
- **Cost Optimized**: 20-25% savings using ARM Graviton vs x86 instances  
- **Secure**: API keys stored in AWS Secrets Manager, encrypted EBS volumes
- **Automated Backups**: Scheduled snapshots to S3 with configurable retention
- **CloudWatch Integration**: Centralized logs and metrics
- **Session Manager**: SSH-less access (no SSH keys needed)
- **EBS Snapshots**: Optional automated volume snapshots with cross-region DR

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    EC2 Qdrant Instance                       │
│                   (ARM64 - Graviton)                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Qdrant v1.7.4 (Native Binary)                       │   │
│  │  - REST API: Port 6333                               │   │
│  │  - gRPC API: Port 6334                               │   │
│  │  - Data: /var/lib/qdrant/storage                     │   │
│  │  - Snapshots: /var/lib/qdrant/snapshots              │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  CloudWatch Agent                                    │   │
│  │  - Application logs → CloudWatch Logs                │   │
│  │  - System metrics → CloudWatch Metrics               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Automated Backup Cron                               │   │
│  │  - Snapshot via Qdrant API                           │   │
│  │  - Upload to S3                                      │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                          │
                          ├─────────► AWS Secrets Manager
                          │            (API Keys)
                          │
                          ├─────────► S3 Bucket
                          │            (Snapshots)
                          │
                          └─────────► CloudWatch
                                       (Logs & Metrics)
```

## Quick Start

### Basic Usage

```hcl
module "qdrant" {
  source = "./databases/ec2_qdrant_arm"

  env        = "production"
  project_id = "myapp"
  base_name  = "vector-db"

  # Network
  subnet_id          = "subnet-xxxxx"
  security_group_ids = ["sg-xxxxx"]

  # Instance (default: t4g.large - 2 vCPU, 8GB RAM, ~$49/month)
  instance_type = "t4g.large"
  storage_size  = 50  # GB for vector data

  # Auto-generated secure API keys
  # Leave empty to auto-generate
  qdrant_api_key           = ""
  qdrant_read_only_api_key = ""

  # Backups (every 6 hours by default)
  enable_automated_backups = true
  backup_schedule          = "0 */6 * * *"
  backup_retention_days    = 7

  tags = {
    Team = "AI/ML"
  }
}
```

### Access Qdrant

```bash
# Get private IP
terraform output -json qdrant | jq -r '.instance.private_ip'

# Get API key from Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id production/myapp/vector-db/qdrant-api-key \
  --query SecretString --output text

# Test connection (from within VPC)
curl http://PRIVATE_IP:6333/

# List collections
curl -H "api-key: YOUR_API_KEY" http://PRIVATE_IP:6333/collections

# Connect via Session Manager (SSH-less)
aws ssm start-session --target i-xxxxx
```

### Instance Types

| Instance     | vCPU | RAM   | Storage     | Cost/Month | Use Case             |
|--------------|------|-------|-------------|------------|----------------------|
| t4g.micro    | 2    | 1 GB  | Burstable   | $6         | Dev/Testing          |
| t4g.small    | 2    | 2 GB  | Burstable   | $12        | Small projects       |
| **t4g.large**| 2    | 8 GB  | Burstable   | **$49**    | **Recommended** ⭐   |
| m7g.large    | 2    | 8 GB  | Steady      | $67        | Production (steady)  |
| m7g.xlarge   | 4    | 16 GB | Steady      | $134       | Large collections    |
| r7g.large    | 2    | 16 GB | Memory-opt  | $84        | Memory-intensive     |

## Configuration Options

### Qdrant Settings

```hcl
# API ports (defaults shown)
qdrant_http_port = 6333  # REST API
qdrant_grpc_port = 6334  # gRPC API

# Logging
qdrant_log_level = "INFO"  # DEBUG, INFO, WARN, ERROR

# API keys (leave empty to auto-generate)
qdrant_api_key           = ""  # Full access
qdrant_read_only_api_key = ""  # Read-only access
```

### Backup Configuration

```hcl
# Automated snapshots
enable_automated_backups = true
backup_schedule          = "0 */6 * * *"  # Every 6 hours
backup_retention_days    = 7

# S3 bucket (auto-created by default)
create_backup_bucket     = true
backup_s3_bucket_name    = ""  # Only if create_backup_bucket = false

# EBS snapshots (optional, additional layer)
enable_ebs_snapshots         = false
ebs_snapshot_interval_hours  = 24
ebs_snapshot_retention_count = 7

# Cross-region disaster recovery
enable_cross_region_snapshot_copy = false
snapshot_dr_region                = "us-west-2"
```

### Monitoring

```hcl
# CloudWatch
enable_cloudwatch_monitoring = true
cloudwatch_retention_days    = 90

# Detailed EC2 metrics (1-min intervals, extra cost)
enable_detailed_monitoring = false
```

## Security

### API Key Management

API keys are stored in AWS Secrets Manager and never exposed in plain text:

```bash
# Retrieve API key
aws secretsmanager get-secret-value \
  --secret-id production/myapp/vector-db/qdrant-api-key \
  --query SecretString --output text

# Use in application
API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id production/myapp/vector-db/qdrant-api-key \
  --query SecretString --output text)

curl -H "api-key: $API_KEY" http://PRIVATE_IP:6333/collections
```

### Network Security

- Deploy in private subnet (recommended)
- Security group must allow:
  - Inbound: 6333 (REST API), 6334 (gRPC) from application subnets
  - Outbound: 443 (HTTPS) for AWS API calls
- No SSH keys needed (use Session Manager)

### Access Control

```bash
# SSH-less access via Session Manager
aws ssm start-session --target i-xxxxx

# Requires:
# - Instance IAM role with AmazonSSMManagedInstanceCore policy (auto-attached)
# - User IAM permissions for ssm:StartSession
```

## Backup & Recovery

### Automated Snapshots

Qdrant snapshots are created via API and uploaded to S3:

```bash
# Manual snapshot (from within instance)
curl -X POST http://localhost:6333/snapshots

# Snapshots stored in S3
s3://BUCKET/YYYY-MM-DD/HHMMSS-qdrant-snapshot.tar.gz
```

### Restore from Snapshot

```bash
# 1. Download snapshot from S3
aws s3 cp s3://BUCKET/2026-02-01/120000-qdrant-snapshot.tar.gz /tmp/

# 2. Extract to snapshots directory
sudo tar -xzf /tmp/120000-qdrant-snapshot.tar.gz -C /var/lib/qdrant/snapshots/

# 3. Restore via Qdrant API
curl -X PUT http://localhost:6333/collections/COLLECTION_NAME/snapshots/recover \
  -H "Content-Type: application/json" \
  -d '{"location":"file:///var/lib/qdrant/snapshots/SNAPSHOT_FILE"}'
```

## Cost Estimation

### Monthly Costs (us-east-1, on-demand)

```
EC2 Instance (t4g.large):        $49.00
EBS Storage (50GB gp3):          $ 4.00
S3 Backups (~10GB):              $ 0.23
CloudWatch Logs (5GB):           $ 2.50
Data Transfer (minimal):         $ 1.00
────────────────────────────────────────
TOTAL:                           ~$57/month
```

**Savings vs x86**: ~20-25% lower cost than comparable t3.large

## Monitoring

### CloudWatch Logs

View logs in CloudWatch:
- `/aws/ec2/PROJECT-ENV-NAME-qdrant`
  - `{instance_id}/setup.log` - Installation logs
  - `{instance_id}/qdrant` - Qdrant application logs
  - `{instance_id}/syslog` - System logs
  - `{instance_id}/backup.log` - Backup logs

### CloudWatch Metrics

Namespace: `Qdrant/EC2`
- CPU_IDLE
- MEM_USED
- DISK_USED

## Outputs

```hcl
# Instance details
module.qdrant.qdrant.instance.private_ip
module.qdrant.qdrant.instance.id

# Connection
module.qdrant.qdrant.connection.rest_api_url
module.qdrant.qdrant.connection.grpc_url

# API keys (sensitive)
module.qdrant.qdrant_api_keys.secrets.get_api_key_cmd

# Session Manager
module.qdrant.connect_via_session_manager
```

## Troubleshooting

### Check Qdrant Status

```bash
# Via Session Manager
aws ssm start-session --target i-xxxxx

# Check service status
sudo systemctl status qdrant

# View logs
sudo journalctl -u qdrant -f
sudo tail -f /var/log/qdrant/qdrant.log

# Test API
curl http://localhost:6333/
```

### Common Issues

**Qdrant not starting:**
```bash
# Check logs
sudo journalctl -u qdrant --no-pager -n 50

# Verify config
sudo cat /etc/qdrant/config.yaml

# Check permissions
sudo ls -la /var/lib/qdrant/
```

**API key authentication failed:**
```bash
# Verify API key in Secrets Manager matches config
aws secretsmanager get-secret-value --secret-id SECRET_ID --query SecretString
```

## Requirements

- Terraform >= 1.0
- AWS Provider >= 4.0
- Ubuntu 24.04 ARM64 AMI (auto-detected)
- VPC with private subnets
- Security groups allowing ports 6333, 6334

## License

MIT

## Support

For issues and questions:
- Qdrant Documentation: https://qdrant.tech/documentation/
- AWS Graviton: https://aws.amazon.com/ec2/graviton/

## Changelog

**v1.0.0** (2026-02-01)
- Initial release
- Native Qdrant v1.7.4 on ARM64
- Automated backups to S3
- CloudWatch integration
- Session Manager support

