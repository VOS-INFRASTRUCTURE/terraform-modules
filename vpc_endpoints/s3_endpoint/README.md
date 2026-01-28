# AWS S3 VPC Endpoints Module
Production-ready Terraform module for creating AWS S3 VPC Endpoints. Provides two endpoint types (Gateway and Interface) for private S3 access from EC2, Lambda, and ECS in private subnets **without requiring NAT Gateway or Internet Gateway**.
## 🎯 Overview
This module creates S3 VPC endpoints allowing your applications to access S3 buckets privately without internet access.
### Two Endpoint Types
| Feature | Gateway Endpoint | Interface Endpoint |
|---------|------------------|---------------------|
| **Cost** | **FREE** | ~$7.20/month per AZ |
| **Works via** | Route table modifications | ENI in subnet |
| **Private DNS** | ❌ No | ✅ Yes |
| **Security Groups** | ❌ No | ✅ Yes |
| **Endpoint Policy** | ✅ Yes | ❌ No |
| **Recommended** | ✅ Default choice | Special cases only |
### Which Should You Use?
**Use Gateway Endpoint (FREE):**
- ✅ Default choice for 99% of use cases
- ✅ EC2, Lambda, ECS in private subnets
- ✅ Want FREE S3 access without NAT
- ✅ Need endpoint policies for security
**Use Interface Endpoint ($7.20/month):**
- Only when Gateway doesn't work
- Need private DNS (s3.region.amazonaws.com)
- Security requires ENI with security groups
- Fully isolated subnet (zero internet)
## 💰 Cost Comparison
### Monthly Cost Breakdown
| Solution | Base Cost | Data Transfer | Total Est. |
|----------|-----------|---------------|------------|
| **NAT Gateway** | $32.40 | $0.045/GB | ~$35-50/month |
| **Gateway Endpoint** (this module) | **FREE** | **FREE (same region)** | **$0** |
| **Interface Endpoint** (1 AZ) | $7.20 | FREE (same region) | ~$8/month |
| **Savings (Gateway)** | -$32.40 | -100% | **~$32-50/month** |
| **Savings (Interface)** | -$25.20 | ~78% cheaper | **~$25-40/month** |
### Cost Formula
```
Gateway Endpoint = FREE (no hourly charge, no data transfer fees)
Interface Endpoint = $0.01/hour × 24 hours × 30 days = $7.20/month per AZ
S3 data transfer (same region) = FREE for both endpoint types
```
## 🏗️ Architecture
### Gateway Endpoint (FREE)
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
│  │  │  ┌──────────────┐                                       │  │  │
│  │  │  │ EC2 Instance │────┐                                  │  │  │
│  │  │  │              │    │ aws s3 cp file.txt s3://bucket   │  │  │
│  │  │  └──────────────┘    │                                  │  │  │
│  │  │                      │                                  │  │  │
│  │  └──────────────────────┼──────────────────────────────────┘  │  │
│  │                         │                                     │  │
│  │  ┌──────────────────────▼─────────────────────────────────┐  │  │
│  │  │ Route Table                                             │  │  │
│  │  │ • 10.0.0.0/16 → local                                  │  │  │
│  │  │ • S3 prefix list → vpce-xxxxx (Gateway Endpoint)       │  │  │
│  │  └────────────────────┬───────────────────────────────────┘  │  │
│  │                       │                                       │  │
│  └───────────────────────┼───────────────────────────────────────┘  │
│                          │                                           │
│                          ▼                                           │
│               ┌────────────────────────┐                             │
│               │ S3 Gateway Endpoint    │                             │
│               │ (FREE - Route based)   │                             │
│               └────────┬───────────────┘                             │
│                        │                                             │
└────────────────────────┼─────────────────────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │ Amazon S3 Service   │
              │  (Managed by AWS)   │
              └─────────────────────┘
```
### Interface Endpoint ($7.20/month)
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
│  │  │  │              │  HTTPS  │ (Private IP: 10.0.1.100) │ │  │  │
│  │  │  │              │   443   │                          │ │  │  │
│  │  │  │ Uploads to:  │         │ S3 Interface Endpoint    │ │  │  │
│  │  │  │ • s3://bucket│         │ ($7.20/month)            │ │  │  │
│  │  │  └──────────────┘         └──────────────────────────┘ │  │  │
│  │  │                                      │                  │  │  │
│  │  └──────────────────────────────────────┼──────────────────┘  │  │
│  │                                         │                     │  │
│  └─────────────────────────────────────────┼─────────────────────┘  │
│                                            │                         │
└────────────────────────────────────────────┼─────────────────────────┘
                                             │
                                             ▼
                              ┌────────────────────────────┐
                              │ Amazon S3 Service          │
                              │    (Managed by AWS)        │
                              └────────────────────────────┘
```
## 📋 Prerequisites
### For Gateway Endpoint (FREE)
| Requirement | Details |
|-------------|---------|
| **IAM Permissions** | Resource needs `s3:*` permissions for target buckets |
| **Route Tables** | VPC must have route tables (auto-detected) |
| **Network** | Resources in subnets associated with route tables |
### For Interface Endpoint ($7.20/month)
| Requirement | Details |
|-------------|---------|
| **IAM Permissions** | Resource needs `s3:*` permissions for target buckets |
| **Security Group** | Must allow outbound HTTPS (443) to VPC CIDR |
| **Gateway Endpoint** | Must exist for private DNS to work |
| **Network** | Resources in same VPC as endpoint |
### IAM Policy Example
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::my-bucket",
        "arn:aws:s3:::my-bucket/*"
      ]
    }
  ]
}
```
## 🚀 Usage
### Minimal Example (Gateway Endpoint - FREE)
```hcl
module "s3_endpoint" {
  source = "../../vpc_endpoints/s3_endpoint"
  # Required variables
  env        = "production"
  project_id = "myapp"
  # Network configuration
  subnet_ids = ["subnet-abc123", "subnet-def456"]
  # Security groups (needed for Interface endpoint)
  resources_security_group_ids = ["sg-ec2-instances"]
  # S3 buckets to allow access
  s3_bucket_arns = [
    "arn:aws:s3:::my-backups-bucket",
    "arn:aws:s3:::my-logs-bucket"
  ]
  # Enable Gateway endpoint (FREE)
  enable_s3_gateway_endpoint = true
  # Disable Interface endpoint (costs money)
  enable_s3_interface_endpoint = false
}
# Cost: $0/month (Gateway is FREE)
```
### Gateway + Interface (for maximum compatibility)
```hcl
module "s3_endpoint" {
  source = "../../vpc_endpoints/s3_endpoint"
  env        = "production"
  project_id = "backend-api"
  # Multiple subnets for HA
  subnet_ids = [
    "subnet-private-a", # eu-west-2a
    "subnet-private-b", # eu-west-2b
  ]
  resources_security_group_ids = [
    "sg-ec2-app-servers",
    "sg-lambda-functions"
  ]
  s3_bucket_arns = [
    "arn:aws:s3:::prod-data-bucket",
    "arn:aws:s3:::prod-backups-bucket"
  ]
  # Enable both endpoints
  enable_s3_gateway_endpoint   = true  # FREE
  enable_s3_interface_endpoint = true  # ~$14.40/month (2 AZs)
}
# Cost: ~$14.40/month (Interface endpoint for 2 AZs)
# Note: Gateway is FREE, costs come from Interface endpoint only
```
### Gateway Only (Recommended)
```hcl
module "s3_endpoint" {
  source = "../../vpc_endpoints/s3_endpoint"
  env        = "staging"
  project_id = "myapp"
  subnet_ids                   = ["subnet-private-a"]
  resources_security_group_ids = ["sg-staging-instances"]
  s3_bucket_arns = [
    "arn:aws:s3:::staging-backups"
  ]
  # Gateway only (FREE)
  enable_s3_gateway_endpoint   = true
  enable_s3_interface_endpoint = false
}
# Cost: $0/month (completely FREE)
# Saves: ~$32.40/month vs NAT Gateway
```
## 📊 Module Inputs
### Required Variables
| Variable | Type | Description |
|----------|------|-------------|
| `env` | `string` | Environment name (e.g., 'production', 'staging') |
| `project_id` | `string` | Project identifier for resource tagging |
| `subnet_ids` | `list(string)` | Subnet IDs (for Interface endpoint) |
| `resources_security_group_ids` | `list(string)` | Security group IDs (for Interface endpoint) |
| `s3_bucket_arns` | `list(string)` | S3 bucket ARNs to allow access |
### Optional Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_s3_gateway_endpoint` | `bool` | `true` | Enable Gateway endpoint (FREE) |
| `enable_s3_interface_endpoint` | `bool` | `false` | Enable Interface endpoint ($7.20/month per AZ) |
## 📤 Module Outputs
### Gateway Endpoint Output
```hcl
output "s3_gateway_endpoint" {
  value = {
    enabled = true
    endpoint = {
      endpoint_id   = "vpce-0123456789abcdef0"
      endpoint_arn  = "arn:aws:ec2:eu-west-2:..."
      service_name  = "com.amazonaws.eu-west-2.s3"
      endpoint_type = "Gateway"
      state         = "available"
    }
    network = {
      vpc_id                  = "vpc-abc123"
      associated_route_tables = ["rtb-xxx", "rtb-yyy"]
    }
    cost = {
      monthly_estimate  = "FREE"
      nat_gateway_saved = "~$32.40/month"
    }
  }
}
```
### Interface Endpoint Output
```hcl
output "s3_interface_endpoint" {
  value = {
    enabled = true
    endpoint = {
      endpoint_id         = "vpce-9876543210fedcba"
      endpoint_arn        = "arn:aws:ec2:eu-west-2:..."
      service_name        = "com.amazonaws.eu-west-2.s3"
      endpoint_type       = "Interface"
      private_dns_enabled = true
      dns_entries         = [...]
    }
    network = {
      vpc_id             = "vpc-abc123"
      subnet_ids         = ["subnet-abc123"]
      security_group_ids = ["sg-endpoint123"]
    }
    cost = {
      monthly_estimate = "~$7.20 USD per AZ"
      net_savings      = "~$25.20/month"
    }
  }
}
```
## 🔧 How to Use S3 with VPC Endpoints
### AWS CLI
```bash
# Upload file to S3 (works with both endpoint types)
aws s3 cp myfile.txt s3://my-bucket/
# List bucket contents
aws s3 ls s3://my-bucket/
# Sync directory
aws s3 sync ./local-dir s3://my-bucket/backup/
# Download file
aws s3 cp s3://my-bucket/file.txt ./
```
### Python (Boto3)
```python
import boto3
# Initialize S3 client (works automatically with VPC endpoints)
s3 = boto3.client('s3')
# Upload file
s3.upload_file('local-file.txt', 'my-bucket', 'remote-file.txt')
# Download file
s3.download_file('my-bucket', 'remote-file.txt', 'local-file.txt')
# List objects
response = s3.list_objects_v2(Bucket='my-bucket')
for obj in response['Contents']:
    print(obj['Key'])
```
### Node.js
```javascript
const AWS = require('aws-sdk');
const s3 = new AWS.S3();
// Upload file
const params = {
  Bucket: 'my-bucket',
  Key: 'file.txt',
  Body: fs.readFileSync('local-file.txt')
};
s3.upload(params, (err, data) => {
  if (err) console.error(err);
  else console.log('Upload successful:', data.Location);
});
// Download file
s3.getObject({ Bucket: 'my-bucket', Key: 'file.txt' }, (err, data) => {
  if (err) console.error(err);
  else fs.writeFileSync('local-file.txt', data.Body);
});
```
## 🔍 Verification
### Check Gateway Endpoint
```bash
# Verify Gateway endpoint is created
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-abc123" \
  --query 'VpcEndpoints[?ServiceName==`com.amazonaws.eu-west-2.s3` && VpcEndpointType==`Gateway`]'
# Check route tables
aws ec2 describe-route-tables \
  --route-table-ids rtb-xxx \
  --query 'RouteTables[].Routes'
```
### Check Interface Endpoint
```bash
# Verify Interface endpoint is created
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-abc123" \
  --query 'VpcEndpoints[?ServiceName==`com.amazonaws.eu-west-2.s3` && VpcEndpointType==`Interface`]'
# Test DNS resolution (should resolve to private IP)
nslookup s3.eu-west-2.amazonaws.com
```
### Test from EC2 Instance
```bash
# Connect to EC2 in private subnet
aws ssm start-session --target i-0123456789abcdef0
# Test S3 access
aws s3 ls s3://my-bucket/
# Verify traffic is using endpoint (check VPC flow logs)
```
## 🐛 Troubleshooting
### Issue: "Unable to connect to S3"
**Possible causes:**
1. **Gateway Endpoint - Route table issue**
   ```bash
   # Check if route table has S3 prefix list route
   aws ec2 describe-route-tables --route-table-ids rtb-xxx
   ```
   **Fix:** Verify endpoint is associated with correct route tables
2. **Interface Endpoint - Security group blocks traffic**
   ```bash
   # Check endpoint security group
   aws ec2 describe-security-groups --group-ids sg-endpoint-xxx
   ```
   **Fix:** Ensure inbound 443 from resource security group
3. **Interface Endpoint - Private DNS not working**
   ```bash
   # Check if Gateway endpoint exists (required for private DNS)
   aws ec2 describe-vpc-endpoints \
     --filters "Name=vpc-endpoint-type,Values=Gateway"
   ```
   **Fix:** Create Gateway endpoint first, then Interface endpoint
### Issue: "Access denied to S3 bucket"
**Possible causes:**
1. **IAM permissions missing**
   ```json
   {
     "Effect": "Allow",
     "Action": ["s3:*"],
     "Resource": ["arn:aws:s3:::my-bucket/*"]
   }
   ```
2. **Endpoint policy blocks bucket**
   - Gateway endpoint: Check endpoint policy in AWS Console
   - Interface endpoint: Use IAM policies instead (no endpoint policies)
### Issue: "High costs"
**Solution:** Use Gateway endpoint only (FREE)
```hcl
# Production: Gateway only (FREE)
enable_s3_gateway_endpoint   = true
enable_s3_interface_endpoint = false
# Only use Interface if Gateway doesn't work
```
## ⚠️ Important Notes
### Critical Requirements
1. **Gateway endpoint is FREE** - Use it as default choice
2. **Interface endpoint costs $7.20/month per AZ** - Only use when needed
3. **Interface requires Gateway for private DNS** - Create Gateway first
4. **Endpoint policies only work with Gateway** - Use IAM for Interface
5. **S3 data transfer in same region is FREE** - No data transfer charges
### Security Best Practices
- ✅ Use Gateway endpoint for cost-effective security
- ✅ Restrict bucket access via endpoint policies (Gateway only)
- ✅ Use IAM policies to restrict S3 access
- ✅ Enable CloudTrail logging for audit trail
- ✅ Review bucket list periodically
- ✅ Follow principle of least privilege
### Cost Optimization
- Use Gateway endpoint only (FREE) for most cases
- Only use Interface endpoint when Gateway doesn't work
- Single subnet deployment for dev/staging to reduce Interface endpoint costs
- Monitor S3 access patterns and adjust endpoint configuration
## 📚 Additional Resources
- [AWS S3 VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [S3 Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/best-practices.html)
## 🔐 Security Considerations
### Network Isolation
- All traffic stays within AWS network (never touches internet)
- No NAT Gateway or Internet Gateway required
- Resources can remain in fully isolated private subnets
### Access Control
**Gateway Endpoint:**
- Endpoint policies restrict bucket access at route level
- IAM policies control user/role permissions
- Bucket policies provide additional layer
**Interface Endpoint:**
- No endpoint policies (use IAM instead)
- Security groups control network access
- IAM policies control user/role permissions
### Audit & Compliance
- All S3 API calls logged to CloudTrail
- VPC flow logs show endpoint usage
- S3 access logs track bucket access
- Integration with AWS Config for compliance checks
## 📝 License
This module is part of the internal Terraform modules library.
## 🤝 Support
For issues or questions:
1. Check the troubleshooting section above
2. Review AWS S3 VPC Endpoints documentation
3. Contact DevOps team
---
**Last Updated:** January 28, 2026  
**Module Version:** 1.0.0  
**Tested with:** Terraform 1.5+, AWS Provider 5.0+
