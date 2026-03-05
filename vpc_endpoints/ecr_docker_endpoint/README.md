# AWS ECR (Docker Registry) VPC Endpoints Module

Production-ready Terraform module for creating Amazon ECR VPC Interface Endpoints. Enables private Docker image pulls from Amazon ECR in ECS tasks, EC2 instances, and Lambda container functions in private subnets **without requiring NAT Gateway or Internet Gateway**.

---

## 🎯 Overview

This module creates **three VPC Interface Endpoints** required for ECR image pulls in private subnets:

| Endpoint | Service Name | Purpose |
|----------|-------------|---------|
| **ECR API** | `com.amazonaws.{region}.ecr.api` | Auth tokens, image metadata, repository management |
| **ECR DKR** | `com.amazonaws.{region}.ecr.dkr` | Docker Registry v2 protocol (actual image pull/push) |
| **S3 Interface** | `com.amazonaws.{region}.s3` | ECR image layer downloads (layers are stored in S3) |

> ⚠️ **ALL THREE endpoints are required.** Missing any one will cause container image pulls to fail silently in private subnets.

---

## 🐳 How Docker Image Pulls Work

Understanding why all three endpoints are needed:

```
Step 1 – Get auth token       →  ecr.api endpoint
   aws ecr get-login-password
   POST ecr.{region}.amazonaws.com/authorization

Step 2 – Docker login         →  ecr.dkr endpoint
   docker login {account}.dkr.ecr.{region}.amazonaws.com
   GET {account}.dkr.ecr.{region}.amazonaws.com/v2/

Step 3 – Pull manifest        →  ecr.dkr endpoint
   GET /v2/{repository}/manifests/{tag}
   (returns list of layer digests to download)

Step 4 – Download layers      →  S3 Interface endpoint
   Each image layer is stored in S3 by ECR.
   Layer URLs are presigned S3 URLs.
   Without S3 Interface endpoint: layer downloads FAIL.
```

---

## ⚠️ Why S3 Interface (Not Gateway)?

This is a common source of confusion:

| Endpoint Type | Private DNS | Works in Private Subnet (no NAT) |
|--------------|-------------|-----------------------------------|
| S3 Gateway | ❌ No | ❌ No — DNS resolves to public IP, connection hangs |
| **S3 Interface** | ✅ Yes | ✅ Yes — DNS resolves to private IP, works perfectly |

ECR layer download URLs point to S3. In private subnets without NAT:
- S3 **Gateway** endpoint: routing works, but DNS still resolves to public IP → AWS SDK/Docker hangs
- S3 **Interface** endpoint: private DNS → private IP → works seamlessly

---

## 💰 Cost Comparison

| Solution | Base Cost | Data Transfer | Notes |
|----------|-----------|---------------|-------|
| **NAT Gateway** | $32.40/month | $0.045/GB | + egress costs for all services |
| **ECR Endpoints (this module)** | $21.60/month | $0.01/GB | 3 endpoints × $7.20 |
| **Savings** | ~$10.80/month | ~78% cheaper | + better security |

> **Note:** Costs are per AZ. Using 2 subnets (2 AZs) doubles the cost to ~$43.20/month.

```
3 Interface Endpoints = 3 × $0.01/hour × 24h × 30 days = $21.60/month
Savings vs NAT        = $32.40 - $21.60 = $10.80/month
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                               Your VPC                                  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      Private Subnet                              │  │
│  │                                                                  │  │
│  │  ┌─────────────────┐                                            │  │
│  │  │  ECS Fargate    │──── HTTPS 443 ──►┌─────────────────────┐  │  │
│  │  │  / EC2 Docker   │                  │ ecr.api endpoint    │  │  │
│  │  │  / Lambda       │──── HTTPS 443 ──►│ ecr.dkr endpoint    │  │  │
│  │  └─────────────────┘                  │ s3 interface endpt  │  │  │
│  │                                       └──────────┬──────────┘  │  │
│  └──────────────────────────────────────────────────│─────────────┘  │
│                                                     │                  │
└─────────────────────────────────────────────────────│──────────────────┘
                                                      │ AWS Internal Network
                                    ┌─────────────────┴──────────────────┐
                                    │         Amazon ECR                  │
                                    │  ┌────────────┐  ┌──────────────┐  │
                                    │  │ ECR API    │  │ ECR Registry │  │
                                    │  └────────────┘  └──────────────┘  │
                                    │           Image Layers              │
                                    │         stored in S3 ──────────────►│
                                    └────────────────────────────────────┘

No internet traffic. No NAT Gateway. Fully private.
```

---

## 📋 Requirements

| Requirement | Detail |
|-------------|--------|
| Terraform | `>= 1.0` |
| AWS Provider | `>= 4.0` |
| VPC DNS Hostnames | Must be **enabled** (`enable_dns_hostnames = true`) |
| VPC DNS Resolution | Must be **enabled** (`enable_dns_support = true`) |
| Resource Outbound | Must allow **HTTPS (443)** to VPC CIDR |
| IAM Permissions | ECS execution role needs `ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, `ecr:GetDownloadUrlForLayer` |

---

## 🚀 Usage

### Minimal Example (ECS Fargate)

```hcl
module "ecr_docker_endpoint" {
  source = "./vpc_endpoints/ecr_docker_endpoint"

  env        = "staging"
  project_id = "myapp"

  subnet_ids                   = ["subnet-abc123", "subnet-def456"]
  resources_security_group_ids = [aws_security_group.ecs_tasks_sg.id]

  enable_ecr_endpoints = true
}
```

### Without Creating S3 Endpoint (Already Exists)

```hcl
module "ecr_docker_endpoint" {
  source = "./vpc_endpoints/ecr_docker_endpoint"

  env        = "production"
  project_id = "myapp"

  subnet_ids                   = module.vpc.private_subnet_ids
  resources_security_group_ids = [
    aws_security_group.ecs_tasks_sg.id,
    aws_security_group.ec2_sg.id,
  ]

  enable_ecr_endpoints = true
  create_s3_endpoint   = false  # S3 Interface endpoint already exists in VPC
}
```

### Full Stack with All Security Endpoints

```hcl
# Session Manager (SSH-less access)
module "session_manager_endpoint" {
  source = "./vpc_endpoints/session_manager_endpoint"
  # ...
}

# Secrets Manager
module "secrets_manager_endpoint" {
  source = "./vpc_endpoints/secret_manager_endpoint"
  # ...
}

# ECR / Docker Registry
module "ecr_docker_endpoint" {
  source = "./vpc_endpoints/ecr_docker_endpoint"

  env        = "production"
  project_id = "myapp"

  subnet_ids                   = module.vpc.private_subnet_ids
  resources_security_group_ids = [aws_security_group.ecs_tasks_sg.id]

  enable_ecr_endpoints = true
  create_s3_endpoint   = true  # Create S3 Interface for ECR layer downloads
}
```

---

## 📥 Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `env` | Environment name (e.g., `staging`, `production`) | `string` | — | ✅ |
| `project_id` | Project identifier for tagging | `string` | — | ✅ |
| `subnet_ids` | List of subnet IDs for endpoint ENIs | `list(string)` | — | ✅ |
| `resources_security_group_ids` | SGs allowed to pull from ECR | `list(string)` | — | ✅ |
| `enable_ecr_endpoints` | Toggle to enable/disable all ECR endpoints | `bool` | `false` | ❌ |
| `create_s3_endpoint` | Create S3 Interface endpoint for layer downloads | `bool` | `true` | ❌ |

---

## 📤 Outputs

| Name | Description |
|------|-------------|
| `ecr_endpoints` | Full endpoint configuration including IDs, ARNs, DNS entries, cost estimates |

### Output Structure

```hcl
ecr_endpoints = {
  enabled = true

  ecr_api = {
    endpoint_id = "vpce-0abc..."
    service_name = "com.amazonaws.eu-west-2.ecr.api"
    # ...
  }

  ecr_dkr = {
    endpoint_id = "vpce-0def..."
    service_name = "com.amazonaws.eu-west-2.ecr.dkr"
    # ...
  }

  s3_interface = {
    endpoint_id = "vpce-0ghi..."
    service_name = "com.amazonaws.eu-west-2.s3"
    created = true
    # ...
  }

  cost = {
    monthly_estimate = "~$21.60 USD (3 endpoints × $7.20/month)"
    savings = "~$10.80/month vs NAT Gateway"
  }
}
```

---

## 🔐 Security Group Rules

The module creates a **single shared security group** for all three endpoints:

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|--------------------|---------|
| **Inbound** | TCP | 443 | `resources_security_group_ids` | Allow HTTPS from ECS/EC2/Lambda |
| **Outbound** | All | All | VPC CIDR | Return traffic within VPC only |

> Your ECS task / EC2 / Lambda security group must allow **outbound TCP 443** to the VPC CIDR.

---

## 🔗 IAM Permissions Required

For ECS Fargate, your **task execution role** needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## ✅ Verification

After applying, verify the endpoints work:

```bash
# From EC2 instance or ECS task in the same VPC/subnet

# 1. Test ECR API (list repositories)
aws ecr describe-repositories --region eu-west-2

# 2. Test ECR authentication
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin \
  {account_id}.dkr.ecr.eu-west-2.amazonaws.com

# 3. Test image pull
docker pull {account_id}.dkr.ecr.eu-west-2.amazonaws.com/{repo}:{tag}

# 4. Describe endpoints
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.eu-west-2.ecr.api" \
  --query "VpcEndpoints[*].{ID:VpcEndpointId,State:State}"
```

---

## ⚠️ Important Notes

1. **VPC DNS must be enabled** — both `enableDnsHostnames` and `enableDnsResolution` must be `true`
2. **All 3 endpoints are mandatory** — missing any one causes silent failures during image pulls
3. **S3 Interface (not Gateway)** — ECR layer downloads require S3 Interface endpoint for private DNS support
4. **IAM still required** — endpoints handle network routing only; IAM roles must still grant ECR permissions
5. **Same subnets as workloads** — endpoint ENIs should be in the same subnets as your ECS tasks / EC2 instances
6. **If S3 Interface already exists** — set `create_s3_endpoint = false` to avoid duplicate endpoint errors

