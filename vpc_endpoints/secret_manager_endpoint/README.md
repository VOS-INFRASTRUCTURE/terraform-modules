# AWS Secrets Manager VPC Endpoint Module
Production-ready Terraform module for creating AWS Secrets Manager VPC Interface Endpoint. Enables private access to AWS Secrets Manager from EC2 instances, Lambda functions, and ECS tasks in private subnets **without requiring NAT Gateway or Internet Gateway**.
## 🎯 Overview
This module creates a single VPC Interface Endpoint for AWS Secrets Manager, allowing your applications to securely retrieve secrets without internet access.
### What is AWS Secrets Manager?
AWS Secrets Manager helps you:
- Store and manage database credentials, API keys, and other secrets
- Automatically rotate secrets (database passwords, API keys)
- Access secrets programmatically via AWS SDK
- Audit secret access via CloudTrail
### Why Use a VPC Endpoint?
| Without VPC Endpoint | With VPC Endpoint (This Module) |
|---------------------|----------------------------------|
| ❌ Requires NAT Gateway ($32.40/month) | ✅ No NAT Gateway needed |
| ❌ Secrets API calls traverse internet | ✅ Traffic stays private in AWS network |
| ❌ Higher data transfer costs ($0.045/GB) | ✅ Lower data transfer costs ($0.01/GB) |
| ❌ Potential security exposure | ✅ Secrets never leave AWS private network |
| ❌ Requires outbound internet access | ✅ Works in fully isolated subnets |
## 💰 Cost Comparison
### Monthly Cost Breakdown
| Solution | Base Cost | Data Transfer | Total Est. |
|----------|-----------|---------------|------------|
| **NAT Gateway** | $32.40 | $0.045/GB | ~$35-50/month |
| **Secrets Manager Endpoint** (this module) | $7.20 | $0.01/GB | ~$8-10/month |
| **Savings** | -$25.20 | ~78% cheaper | **~$25-40/month** |
> **Note:** Costs are for single AZ deployment. Multi-AZ deployments multiply endpoint costs by number of AZs.
### Cost Formula
```
Interface Endpoint Cost = $0.01/hour × 24 hours × 30 days = $7.20/month
Savings vs NAT Gateway = $32.40 - $7.20 = $25.20/month
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
│  │  │  │ (App Server) │  HTTPS  │ (Private IP: 10.0.1.100) │ │  │  │
│  │  │  │              │   443   │                          │ │  │  │
│  │  │  │ Fetches:     │         │ secretsmanager endpoint  │ │  │  │
│  │  │  │ • DB password│         │                          │ │  │  │
│  │  │  │ • API keys   │         │                          │ │  │  │
│  │  │  └──────────────┘         └──────────────────────────┘ │  │  │
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
                              │ AWS Secrets Manager Service │
                              │    (Managed by AWS)         │
                              └────────────────────────────┘
```
### Traffic Flow
1. **Application makes API call**:
   ```python
   import boto3
   client = boto3.client('secretsmanager')
   response = client.get_secret_value(SecretId='prod/db/password')
   ```
2. **Request flows**:
   - Application → VPC Endpoint (private IP 10.x.x.x)
   - VPC Endpoint → Secrets Manager Service (via AWS PrivateLink)
   - Secrets Manager → VPC Endpoint → Application
3. **All traffic stays private** - no NAT, no IGW, no public IPs!
## 📋 Prerequisites
### Resource Requirements
| Requirement | Details |
|-------------|---------|
| **IAM Permissions** | Resource needs `secretsmanager:GetSecretValue` (and other actions as needed) |
| **Security Group** | Must allow outbound HTTPS (443) to VPC CIDR |
| **Network** | Can be in private subnet (no public IP needed) |
| **Subnet** | Must be in same VPC as VPC endpoint |
### IAM Policy Example
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:prod/*"
    }
  ]
}
```
### Resource Security Group
```hcl
# Your EC2/Lambda/ECS security group must allow outbound HTTPS
resource "aws_security_group" "app" {
  # ... other configuration ...
  egress {
    description = "Allow outbound HTTPS for Secrets Manager"
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
module "secretsmanager_endpoint" {
  source = "../../vpc_endpoints/secret_manager_endpoint"
  # Required variables
  env        = "production"
  project_id = "myapp"
  # Network configuration
  subnet_ids = ["subnet-abc123", "subnet-def456"] # Private subnets
  # Security groups of resources that need Secrets Manager access
  resources_security_group_ids = ["sg-ec2-app-servers"]
  # Enable endpoint (default: false to avoid costs)
  enable_secretsmanager_endpoint = true
}
```
### Multi-Resource Example
```hcl
module "secretsmanager_endpoint" {
  source = "../../vpc_endpoints/secret_manager_endpoint"
  env        = "production"
  project_id = "backend-api"
  # Multiple subnets for HA (different AZs)
  subnet_ids = [
    "subnet-private-a", # eu-west-2a
    "subnet-private-b", # eu-west-2b
  ]
  # Multiple resource security groups
  resources_security_group_ids = [
    "sg-web-servers",
    "sg-app-servers",
    "sg-lambda-functions",
    "sg-ecs-tasks",
  ]
  enable_secretsmanager_endpoint = true
}
```
### Cost-Optimized (Single Subnet)
```hcl
module "secretsmanager_endpoint" {
  source = "../../vpc_endpoints/secret_manager_endpoint"
  env        = "staging"
  project_id = "myapp"
  # Single subnet for cost optimization
  subnet_ids = ["subnet-private-a"]
  resources_security_group_ids = ["sg-staging-instances"]
  enable_secretsmanager_endpoint = true
}
# Cost: ~$7.20/month (single AZ)
# vs Multi-AZ: ~$14.40/month (2 AZs)
```
### Disable Endpoint (Use NAT Gateway Instead)
```hcl
module "secretsmanager_endpoint" {
  source = "../../vpc_endpoints/secret_manager_endpoint"
  env        = "dev"
  project_id = "myapp"
  subnet_ids                   = ["subnet-private-a"]
  resources_security_group_ids = ["sg-dev-instances"]
  # Disabled - resources will use NAT Gateway or public internet
  enable_secretsmanager_endpoint = false
}
# Cost: $0 (endpoint not created)
# Note: Requires NAT Gateway (~$32.40/month) or IGW for Secrets Manager access
```
## 📊 Module Inputs
### Required Variables
| Variable | Type | Description |
|----------|------|-------------|
| `env` | `string` | Environment name (e.g., 'production', 'staging', 'dev') |
| `project_id` | `string` | Project identifier for resource tagging |
| `subnet_ids` | `list(string)` | List of subnet IDs where endpoint will be created |
| `resources_security_group_ids` | `list(string)` | Security group IDs of resources needing access |
### Optional Variables
| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_secretsmanager_endpoint` | `bool` | `false` | Enable/disable endpoint creation |
## 📤 Module Outputs
### Output Structure
```hcl
output "secretsmanager_endpoint" {
  value = {
    enabled = true
    # Endpoint details
    endpoint = {
      endpoint_id         = "vpce-0123456789abcdef0"
      endpoint_arn        = "arn:aws:ec2:eu-west-2:..."
      service_name        = "com.amazonaws.eu-west-2.secretsmanager"
      private_dns_enabled = true
      dns_entries         = []
    }
    # Network configuration
    network = {
      vpc_id             = "vpc-abc123"
      subnet_ids         = ["subnet-abc123"]
      security_group_ids = ["sg-endpoints123"]
      vpc_cidr_block     = "10.0.0.0/16"
    }
    # Cost information
    cost = {
      monthly_estimate = "~$7.20 USD"
      comparison       = "NAT Gateway: ~$32.40/month"
      savings          = "~$25.20/month"
    }
    # Usage examples
    usage = {
      aws_cli_example = "aws secretsmanager get-secret-value --secret-id my-database-password"
      python_example  = "boto3.client('secretsmanager').get_secret_value(SecretId='my-secret')"
      nodejs_example  = "new AWS.SecretsManager().getSecretValue({SecretId: 'my-secret'})"
      requirements    = []
    }
  }
}
```
### Accessing Outputs
```hcl
# Get endpoint ID
output "endpoint_id" {
  value = module.secretsmanager_endpoint.secretsmanager_endpoint.endpoint.endpoint_id
}
# Get cost estimate
output "monthly_cost" {
  value = module.secretsmanager_endpoint.secretsmanager_endpoint.cost.monthly_estimate
}
```
## 🔧 How to Use Secrets Manager
### AWS CLI
```bash
# Retrieve a secret
aws secretsmanager get-secret-value \
  --secret-id prod/database/password \
  --query SecretString \
  --output text
# List secrets
aws secretsmanager list-secrets
# Create a new secret
aws secretsmanager create-secret \
  --name prod/api/third-party-key \
  --secret-string '{"api_key":"abc123xyz"}'
```
### Python (Boto3)
```python
import boto3
import json
# Initialize client
client = boto3.client('secretsmanager')
# Retrieve secret
response = client.get_secret_value(SecretId='prod/database/password')
secret_dict = json.loads(response['SecretString'])
# Access values
db_password = secret_dict['password']
db_username = secret_dict['username']
db_host = secret_dict['host']
# Use in application
connection = psycopg2.connect(
    host=db_host,
    user=db_username,
    password=db_password,
    database='myapp'
)
```
### Node.js
```javascript
const AWS = require('aws-sdk');
const secretsManager = new AWS.SecretsManager();
async function getSecret(secretName) {
  try {
    const data = await secretsManager.getSecretValue({
      SecretId: secretName
    }).promise();
    return JSON.parse(data.SecretString);
  } catch (error) {
    console.error('Error retrieving secret:', error);
    throw error;
  }
}
// Usage
(async () => {
  const dbCreds = await getSecret('prod/database/credentials');
  console.log('Database host:', dbCreds.host);
})();
```
### Docker/ECS
```dockerfile
# No code changes needed!
# Just ensure:
# 1. ECS task has IAM role with secretsmanager:GetSecretValue
# 2. Task security group allows outbound 443
# 3. Task runs in VPC with Secrets Manager endpoint
# Application code works exactly the same
```
## 🔍 Verification
### Check Endpoint Status
```bash
# Verify endpoint is created
aws ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=vpc-abc123" \
  --query 'VpcEndpoints[?ServiceName==`com.amazonaws.eu-west-2.secretsmanager`]'
```
### Test from EC2 Instance
```bash
# Connect to EC2 in private subnet
aws ssm start-session --target i-0123456789abcdef0
# Once connected, verify DNS resolution
nslookup secretsmanager.eu-west-2.amazonaws.com
# Should resolve to private IP (10.x.x.x)
# Test secret retrieval
aws secretsmanager get-secret-value --secret-id test-secret
```
## 🐛 Troubleshooting
### Issue: "Unable to connect to endpoint"
**Possible causes:**
1. **Missing outbound rule in resource security group**
   ```bash
   # Check security group rules
   aws ec2 describe-security-groups --group-ids sg-xxx
   ```
   **Fix:** Add outbound HTTPS (443) to VPC CIDR
2. **Endpoint security group blocks traffic**
   ```bash
   # Check endpoint security group
   aws ec2 describe-security-groups --group-ids <endpoint-sg-id>
   ```
   **Fix:** Ensure inbound 443 from resource security group
3. **Private DNS not enabled**
   ```bash
   # Check endpoint configuration
   aws ec2 describe-vpc-endpoints --vpc-endpoint-ids vpce-xxx
   ```
   **Fix:** `private_dns_enabled` must be `true`
### Issue: "Access denied"
**Possible causes:**
1. **IAM permissions missing**
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "secretsmanager:GetSecretValue"
     ],
     "Resource": "arn:aws:secretsmanager:*:*:secret:*"
   }
   ```
2. **Secret doesn't exist or wrong region**
   ```bash
   # List available secrets
   aws secretsmanager list-secrets
   ```
### Issue: "High costs"
**Solution:** Use single-subnet deployment for non-production environments
```hcl
# Production: Multi-AZ for HA (~$14/month)
subnet_ids = ["subnet-a", "subnet-b"]
# Staging/Dev: Single AZ for cost savings (~$7/month)
subnet_ids = ["subnet-a"]
```
## ⚠️ Important Notes
### Critical Requirements
1. **Private DNS must be enabled** - Set to `true` on endpoint (this module does automatically)
2. **IAM permissions required** - Resource needs appropriate `secretsmanager:*` permissions
3. **Security groups must allow HTTPS (443)** - Both resource and endpoint security groups
4. **Same VPC requirement** - Resources must be in same VPC as endpoint
### Security Best Practices
- ✅ Use separate security group for endpoint (this module does this automatically)
- ✅ Restrict endpoint egress to VPC CIDR only (not 0.0.0.0/0)
- ✅ Use IAM policies to restrict which secrets can be accessed
- ✅ Enable CloudTrail logging for audit trail
- ✅ Use secret rotation for database credentials
- ✅ Never hardcode secrets in application code
### Cost Optimization
- Use single subnet for dev/staging environments
- Use multi-subnet for production (HA)
- If you already have NAT Gateway for other services, evaluate if endpoint is cost-effective
- Monitor data transfer costs (usually negligible for Secrets Manager)
## 📚 Additional Resources
- [AWS Secrets Manager Documentation](https://docs.aws.amazon.com/secretsmanager/)
- [VPC Endpoints Pricing](https://aws.amazon.com/privatelink/pricing/)
- [Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [Secret Rotation Guide](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
## 🔐 Security Considerations
### Network Isolation
- All traffic stays within AWS network (never touches internet)
- No NAT Gateway or Internet Gateway required
- Resources can remain in fully isolated private subnets
### Access Control
- IAM-based authentication (no hardcoded credentials)
- Fine-grained permissions per secret
- Supports resource-based policies on secrets
- Integration with AWS Organizations for cross-account access
### Audit & Compliance
- All API calls logged to CloudTrail
- Secret access tracked and auditable
- Supports secret versioning and rotation
- Integration with AWS Config for compliance checks
## 📝 License
This module is part of the internal Terraform modules library.
## 🤝 Support
For issues or questions:
1. Check the troubleshooting section above
2. Review AWS Secrets Manager documentation
3. Contact DevOps team
---
**Last Updated:** January 28, 2026  
**Module Version:** 1.0.0  
**Tested with:** Terraform 1.5+, AWS Provider 5.0+
