# EC2 Docker Server - Security Architecture

## 🔒 Security Overview

This module implements security best practices for EC2 instances running Docker workloads.

## Security Features

### 1. Encrypted Storage

**EBS Volume Encryption:**
- All EBS volumes encrypted at rest using AWS managed keys
- Encryption enabled by default (`enable_ebs_encryption = true`)
- No performance impact
- Automatic key rotation managed by AWS

```hcl
root_block_device {
  encrypted = true  # Always enabled for production
}
```

### 2. IAM Roles (Least Privilege)

**What the EC2 instance CAN do:**

| Service | Permission | Purpose |
|---------|-----------|---------|
| **CloudWatch Logs** | `CreateLogGroup` | Create log groups |
| **CloudWatch Logs** | `CreateLogStream` | Create log streams |
| **CloudWatch Logs** | `PutLogEvents` | Send application logs |
| **CloudWatch** | `PutMetricData` | Send custom metrics |
| **SSM** | Session Manager | SSH-less instance access |

**What the EC2 instance CANNOT do (by design):**

| Service | Blocked Actions | Why? |
|---------|----------------|------|
| **IAM** | Any action | Cannot modify its own permissions |
| **EC2** | Launch/Terminate | Cannot create more instances |
| **S3** | Any action (unless explicitly added) | No unauthorized access |
| **Secrets Manager** | Any action (unless explicitly added) | Scope must be explicit |

### 3. Instance Metadata Service v2 (IMDSv2)

**Enforced by default to prevent SSRF attacks:**

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # IMDSv2 enforced
  http_put_response_hop_limit = 1
}
```

**Benefits:**
- Session-based access (prevents SSRF attacks)
- Defense-in-depth against credential theft
- Industry best practice for modern EC2 deployments

**What this prevents:**
```bash
# ❌ This attack vector is blocked (IMDSv1 disabled):
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/

# ✅ Only authenticated requests allowed (IMDSv2):
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/
```

### 4. SSH-less Access via Session Manager

**Recommended: SSM Session Manager (no SSH keys needed)**

```bash
# Connect to instance without SSH keys
aws ssm start-session --target i-0123456789abcdef
```

**Benefits:**
- No SSH keys to manage or rotate
- IAM-based access control
- All sessions logged in CloudTrail
- No port 22 open in security groups
- Works in private subnets without bastion hosts

**Security comparison:**

| Feature | SSH Keys | SSM Session Manager |
|---------|----------|---------------------|
| **Key management** | Manual rotation needed | No keys to manage |
| **Access control** | Security group + key file | IAM policies |
| **Audit trail** | SSH logs only | CloudTrail + Session logs |
| **Network exposure** | Port 22 open | No inbound ports needed |
| **MFA support** | Limited | Native IAM MFA |
| **Bastion required** | Yes (for private subnets) | No |

### 5. Network Security

**Private Subnet Deployment (Recommended):**

```hcl
module "docker_server" {
  source = "../../ec2_servers/ec2_x86_docker"
  
  subnet_id          = "subnet-private-1a"  # Private subnet
  security_group_ids = ["sg-app-servers"]
}
```

**Required for SSM in Private Subnets:**

Option A: VPC Endpoints (no internet access needed)
```
Required endpoints:
- com.amazonaws.region.ssm
- com.amazonaws.region.ssmmessages
- com.amazonaws.region.ec2messages
```

Option B: NAT Gateway (for general internet access)

### 6. Termination Protection

**Prevent accidental deletion:**

```hcl
module "docker_server" {
  source = "../../ec2_servers/ec2_x86_docker"
  
  enable_termination_protection = true  # Recommended for production
}
```

**What this protects:**
- ✅ Prevents accidental `terraform destroy`
- ✅ Prevents manual instance termination via console
- ✅ Protects against script errors

**Note:** EBS snapshots persist independently, even if instance is terminated.

## Security Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Terraform Deployment                                     │
│    - Creates IAM role with least-privilege policies         │
│    - Creates EC2 instance with IMDSv2 enforced             │
│    - Encrypts EBS volumes                                   │
│    - Configures CloudWatch monitoring                       │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. EC2 Instance (Docker Server)                            │
│    - Runs in private subnet (recommended)                   │
│    - No SSH access (SSM Session Manager only)              │
│    - Limited IAM permissions (CloudWatch + SSM only)       │
│    - IMDSv2 enforced (prevents SSRF attacks)               │
│    - Docker pre-installed and ready to use                 │
└─────────────────────────────────────────────────────────────┘
                           ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Monitoring & Backups                                     │
│    - CloudWatch Logs: System + application logs             │
│    - CloudWatch Metrics: CPU, memory, disk usage           │
│    - EBS Snapshots: Automated via Data Lifecycle Manager   │
│    - All encrypted at rest and in transit                  │
└─────────────────────────────────────────────────────────────┘
```

## Access Control Model

### Who Can Do What

| Action | Terraform | EC2 Instance | Admins (IAM) |
|--------|-----------|--------------|--------------|
| **Create instance** | ✅ Yes | ❌ No | ✅ Yes |
| **Terminate instance** | ✅ Yes | ❌ No | ✅ Yes |
| **Modify IAM role** | ✅ Yes | ❌ No | ✅ Yes |
| **Create snapshots** | ✅ Yes (via DLM) | ❌ No | ✅ Yes |
| **Access via SSM** | ❌ No | N/A | ✅ Yes (if IAM allows) |
| **Write CloudWatch Logs** | ❌ No | ✅ Yes | ✅ Yes |
| **Run Docker containers** | ❌ No | ✅ Yes (via SSM) | ✅ Yes (via SSM) |

## Security Best Practices

### ✅ Before Production Deployment

- [ ] Deploy in **private subnet**
- [ ] Enable **EBS encryption** (`enable_ebs_encryption = true`)
- [ ] Enable **CloudWatch monitoring** (`enable_cloudwatch_monitoring = true`)
- [ ] Enable **EBS snapshots** (`enable_ebs_snapshots = true`)
- [ ] Use **SSM Session Manager** only (disable SSH: `enable_ssh_key_access = false`)
- [ ] Restrict **security group** to minimum required ports
- [ ] Enable **termination protection** (`enable_termination_protection = true`)
- [ ] Set up **CloudWatch alarms** for critical metrics
- [ ] Test **snapshot restore procedure**
- [ ] Review and audit **IAM policies**
- [ ] Configure **VPC endpoints** (if no NAT Gateway)
- [ ] Enable **CloudTrail** logging for audit trail

### ⚠️ Common Security Mistakes to Avoid

| ❌ Don't Do This | ✅ Do This Instead |
|-----------------|-------------------|
| Deploy in public subnet | Deploy in private subnet |
| Use SSH keys | Use SSM Session Manager |
| Allow 0.0.0.0/0 in security groups | Restrict to specific CIDR blocks |
| Disable EBS encryption | Always enable encryption |
| Skip CloudWatch monitoring | Enable monitoring and alarms |
| Manually manage snapshots | Use automated EBS snapshots |
| Give EC2 admin permissions | Use least-privilege IAM roles |
| Ignore CloudTrail logs | Enable and monitor CloudTrail |

## Compliance & Auditing

### CloudTrail Integration

All API calls are logged in CloudTrail:
- EC2 instance launch/terminate
- IAM role usage
- SSM Session Manager connections
- EBS snapshot creation
- CloudWatch API calls

### Session Recording

All SSM sessions can be logged:
```hcl
# Enable session logging (add to your infrastructure)
resource "aws_ssm_document" "session_logging" {
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Document to hold regional settings for Session Manager"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = "my-session-logs-bucket"
      cloudWatchLogGroupName      = "/aws/ssm/session-logs"
      cloudWatchEncryptionEnabled = true
    }
  })
}
```

## Incident Response

### If Instance is Compromised

1. **Immediate actions:**
   ```bash
   # Isolate instance (update security group to block all traffic)
   aws ec2 modify-instance-attribute \
     --instance-id i-xxx \
     --groups sg-isolated
   
   # Create forensic snapshot
   aws ec2 create-snapshot \
     --volume-id vol-xxx \
     --description "Forensic snapshot - incident $(date)"
   ```

2. **Investigation:**
   - Review CloudTrail logs
   - Review SSM session history
   - Review CloudWatch Logs for suspicious activity
   - Analyze Docker container logs

3. **Recovery:**
   - Launch new instance from last known good snapshot
   - Rotate all credentials
   - Update security groups
   - Review and update IAM policies

4. **Post-incident:**
   - Document findings
   - Update security policies
   - Implement additional monitoring
   - Conduct security review

## Additional Resources

- [AWS Security Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp.html)
- [IMDSv2 Deep Dive](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)
- [SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)

---

**Module implements defense-in-depth security!** 🔒

