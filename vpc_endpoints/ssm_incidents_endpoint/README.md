# AWS SSM Incidents (Incident Manager) VPC Endpoint Module

Production-ready Terraform module for creating an AWS SSM Incidents VPC Interface Endpoint. Enables private access to the AWS Systems Manager Incident Manager **Incidents API** from EC2 instances, Lambda functions, and ECS tasks in private subnets **without requiring NAT Gateway or Internet Gateway**.

---

## 🎯 Overview

This module creates a VPC Interface Endpoint for `com.amazonaws.{region}.ssm-incidents`, allowing your compute resources to call the Incident Manager Incidents API securely without internet access.

### What is AWS SSM Incidents / Incident Manager?

AWS Systems Manager Incident Manager is an incident management console that helps teams prepare for and respond to operational incidents. The **Incidents** API specifically manages:

- **Incident records** — open, update, close incidents with severity and impact
- **Response plans** — automated runbooks triggered when incidents start
- **Timeline events** — chronological log of what happened during an incident
- **Related items** — link OpsItems, metrics, runbooks, and Slack channels to incidents
- **Replication sets** — cross-Region incident data replication for resilience

### ssm-incidents vs ssm-contacts

| Endpoint | What It Manages |
|----------|-----------------|
| `ssm-incidents` | **What happened** — incident records, timeline, response plans, impact |
| `ssm-contacts` | **Who to notify** — on-call schedules, escalation plans, contact channels |

Both are typically used together for full Incident Manager functionality. Use separate modules for each.

### Why Use a VPC Endpoint?

| Without VPC Endpoint | With VPC Endpoint (This Module) |
|---------------------|----------------------------------|
| ❌ Requires NAT Gateway (~$32.40/month) | ✅ No NAT Gateway needed |
| ❌ Incident API calls traverse internet | ✅ Traffic stays private in AWS network |
| ❌ Higher data transfer costs ($0.045/GB) | ✅ Lower data transfer costs ($0.01/GB) |
| ❌ Security risk (internet exposure) | ✅ API calls never leave AWS private network |
| ❌ Requires outbound internet access | ✅ Works in fully isolated private subnets |

---

## 💰 Cost Comparison

| Solution | Base Cost | Data Transfer | Total Est. |
|----------|-----------|---------------|------------|
| **NAT Gateway** | $32.40/month | $0.045/GB | ~$35–50/month |
| **SSM Incidents Endpoint** (this module) | $7.20/month | $0.01/GB | ~$8–10/month |
| **Savings** | ~$25.20/month | ~78% cheaper | **~$25–40/month** |

> **Note:** Costs are per AZ. Multi-AZ deployments multiply endpoint cost by number of AZs.

```
Interface Endpoint Cost = $0.01/hour × 24 hours × 30 days = $7.20/month
Savings vs NAT Gateway  = $32.40 - $7.20 = $25.20/month
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Your VPC                                │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │                  Private Subnet                         │   │
│  │                                                         │   │
│  │  ┌──────────────┐       HTTPS (443)                    │   │
│  │  │  EC2 / Lambda │─────────────────────────────┐       │   │
│  │  │  / ECS Task   │                             │       │   │
│  │  └──────────────┘                             ▼       │   │
│  │                                  ┌─────────────────────┐  │
│  │                                  │  VPC Interface      │  │
│  │                                  │  Endpoint           │  │
│  │                                  │  (ssm-incidents)    │  │
│  │                                  └──────────┬──────────┘  │
│  └─────────────────────────────────────────────│─────────────┘│
│                                                │               │
└────────────────────────────────────────────────│───────────────┘
                                                 │
                                                 │ AWS Internal Network
                                                 ▼
                                    ┌────────────────────────┐
                                    │  AWS Systems Manager   │
                                    │  Incident Manager API  │
                                    │  (ssm-incidents)       │
                                    └────────────────────────┘

No internet traffic. No NAT Gateway. Fully private.
```

---

## 📋 Requirements

| Requirement | Detail |
|-------------|--------|
| Terraform | `>= 1.0` |
| AWS Provider | `>= 4.0` |
| VPC DNS Hostnames | Must be **enabled** on your VPC |
| VPC DNS Resolution | Must be **enabled** on your VPC |
| EC2 Outbound | Must allow **HTTPS (443)** to VPC CIDR |

---

## 🚀 Usage

### Minimal Example

```hcl
module "ssm_incidents_endpoint" {
  source = "./vpc_endpoints/ssm_incidents_endpoint"

  env        = "staging"
  project_id = "myapp"

  subnet_ids                   = ["subnet-abc123", "subnet-def456"]
  resources_security_group_ids = ["sg-ec2abc123"]

  enable_ssm_incidents_endpoint = true
}
```

### With Lambda Function

```hcl
module "ssm_incidents_endpoint" {
  source = "./vpc_endpoints/ssm_incidents_endpoint"

  env        = "production"
  project_id = "myapp"

  subnet_ids = module.vpc.private_subnet_ids
  resources_security_group_ids = [
    aws_security_group.lambda_sg.id,
    aws_security_group.ec2_sg.id,
  ]

  enable_ssm_incidents_endpoint = true
}
```

---

## 📥 Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| `env` | Environment name (e.g., `staging`, `production`) | `string` | — | ✅ |
| `project_id` | Project identifier for tagging | `string` | — | ✅ |
| `subnet_ids` | List of subnet IDs for endpoint ENIs | `list(string)` | — | ✅ |
| `resources_security_group_ids` | SGs allowed to call the endpoint | `list(string)` | — | ✅ |
| `enable_ssm_incidents_endpoint` | Toggle to enable/disable endpoint | `bool` | `false` | ❌ |

---

## 📤 Outputs

| Name | Description |
|------|-------------|
| `ssm_incidents_endpoint` | Full endpoint configuration including ID, ARN, DNS entries, network info, cost estimates |

### Output Structure

```hcl
ssm_incidents_endpoint = {
  enabled = true

  endpoint = {
    endpoint_id         = "vpce-0abc123..."
    endpoint_arn        = "arn:aws:ec2:..."
    service_name        = "com.amazonaws.eu-west-2.ssm-incidents"
    private_dns_enabled = true
    dns_entries         = [...]
  }

  network = {
    vpc_id             = "vpc-..."
    subnet_ids         = ["subnet-..."]
    security_group_ids = ["sg-..."]
    vpc_cidr_block     = "10.0.0.0/16"
  }

  cost = {
    monthly_estimate = "~$7.20 USD + minimal data transfer"
    comparison       = "NAT Gateway alternative: ~$32.40/month"
    savings          = "~$25.20/month"
  }
}
```

---

## 🔐 Security Group Rules

The module creates a dedicated security group for the endpoint:

| Direction | Protocol | Port | Source/Destination | Purpose |
|-----------|----------|------|--------------------|---------|
| **Inbound** | TCP | 443 | `resources_security_group_ids` | Allow HTTPS from your resources |
| **Outbound** | All | All | VPC CIDR | Return traffic within VPC only |

> Your EC2/Lambda/ECS security group must allow **outbound TCP 443** to the VPC CIDR.

---

## 🔗 Related Endpoints

For full Incident Manager + Session Manager functionality, combine with:

| Module | Service | Purpose |
|--------|---------|---------|
| `ssm_incidents_endpoint` | `ssm-incidents` | **This module** — Incident records & response plans |
| `system_manager_contacts` | `ssm-contacts` | On-call schedules, contact channels, escalation plans |
| `session_manager_endpoint` | `ssm`, `ssmmessages`, `ec2messages` | SSH-less access to EC2 via Session Manager |
| `secret_manager_endpoint` | `secretsmanager` | Secrets Manager private access |

---

## ✅ Verification

After applying, verify the endpoint works:

```bash
# From EC2 instance in the same VPC/subnet
aws ssm-incidents list-incident-records --region eu-west-2

# Check response plans
aws ssm-incidents list-response-plans --region eu-west-2

# Describe endpoint
aws ec2 describe-vpc-endpoints \
  --filters "Name=service-name,Values=com.amazonaws.eu-west-2.ssm-incidents" \
  --query "VpcEndpoints[*].{ID:VpcEndpointId,State:State,DNS:DnsEntries[0].DnsName}"
```

---

## ⚠️ Important Notes

1. **VPC DNS must be enabled** — both `enableDnsHostnames` and `enableDnsResolution` must be `true` on the VPC
2. **Private DNS is mandatory** — `private_dns_enabled = true` is set automatically; without it standard SDK calls will fail
3. **IAM permissions still required** — the endpoint handles network routing only; IAM roles must still grant `ssm-incidents:*` permissions
4. **Not the same as ssm-contacts** — this endpoint only covers incident records/response plans; for contact management, also deploy `system_manager_contacts` module

