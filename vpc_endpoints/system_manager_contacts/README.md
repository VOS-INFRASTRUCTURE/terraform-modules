# AWS SSM Contacts (Incident Manager) VPC Endpoint Module

Production-ready Terraform module for creating an AWS SSM Contacts VPC Interface Endpoint. Enables private access to the AWS Systems Manager Incident Manager Contacts API from EC2 instances, Lambda functions, and ECS tasks in private subnets **without requiring NAT Gateway or Internet Gateway**.

---

## 🎯 Overview

This module creates a VPC Interface Endpoint for `com.amazonaws.{region}.ssm-contacts`, allowing your compute resources to call the Incident Manager Contacts API securely without internet access.

### What is AWS SSM Contacts / Incident Manager?

AWS Systems Manager Incident Manager is an incident management console that helps teams prepare for and respond to operational incidents. The **Contacts** API specifically manages:

- **On-call schedules** — who is responsible right now
- **Escalation plans** — what happens if nobody responds
- **Contact channels** — email, SMS, voice for each responder
- **Engagements** — notify contacts when an incident occurs
- **Rotations** — rotating on-call schedules across teams

### Why Use a VPC Endpoint?

| Without VPC Endpoint | With VPC Endpoint (This Module) |
|---------------------|----------------------------------|
| ❌ Requires NAT Gateway (~$32.40/month) | ✅ No NAT Gateway needed |
| ❌ Incident Manager API calls traverse internet | ✅ Traffic stays private in AWS network |
| ❌ Higher data transfer costs ($0.045/GB) | ✅ Lower data transfer costs ($0.01/GB) |
| ❌ Security risk (internet exposure) | ✅ API calls never leave AWS private network |
| ❌ Requires outbound internet access | ✅ Works in fully isolated private subnets |

---

## 💰 Cost Comparison

| Solution | Base Cost | Data Transfer | Total Est. |
|----------|-----------|---------------|------------|
| **NAT Gateway** | $32.40/month | $0.045/GB | ~$35–50/month |
| **SSM Contacts Endpoint** (this module) | $7.20/month | $0.01/GB | ~$8–10/month |
| **Savings** | ~$25.20/month | ~78% cheaper | **~$25–40/month** |

> **Note:** Costs are per AZ. Multi-AZ deployments multiply endpoint cost by number of AZs.

```
Interface Endpoint Cost = $0.01/hour × 24 hours × 30 days = $7.20/month
Savings vs NAT Gateway  = $32.40 - $7.20 = $25.20/month
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                      AWS Region (eu-west-2)                          │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │                   VPC (10.0.0.0/16)                           │  │
│  │                                                               │  │
│  │  ┌─────────────────────────────────────────────────────────┐ │  │
│  │  │          Private Subnet (10.0.1.0/24)                   │ │  │
│  │  │                                                         │ │  │
│  │  │  ┌────────────────┐      ┌──────────────────────────┐  │ │  │
│  │  │  │ EC2 / Lambda   │─────▶│ VPC Endpoint ENI         │  │ │  │
│  │  │  │ (Automation)   │ HTTPS│ (Private IP: 10.0.1.x)   │  │ │  │
│  │  │  │                │  443 │                          │  │ │  │
│  │  │  │ Creates:       │      │  ssm-contacts endpoint   │  │ │  │
│  │  │  │ • engagements  │      │                          │  │ │  │
│  │  │  │ • contacts     │      │                          │  │ │  │
│  │  │  │ • rotations    │      │                          │  │ │  │
│  │  │  └────────────────┘      └──────────────────────────┘  │ │  │
│  │  │                                       │                 │ │  │
│  │  └───────────────────────────────────────┼─────────────────┘ │  │
│  │                                          │                   │  │
│  └──────────────────────────────────────────┼───────────────────┘  │
│                                             │                       │
│                    ┌────────────────────────┼────────────────────┐  │
│                    │  AWS PrivateLink Network (Internal AWS)     │  │
│                    └────────────────────────┼────────────────────┘  │
│                                             │                       │
└─────────────────────────────────────────────┼───────────────────────┘
                                              ▼
                          ┌─────────────────────────────────┐
                          │ AWS Incident Manager Contacts   │
                          │        Service (Managed)        │
                          └─────────────────────────────────┘
```

### Traffic Flow

1. Lambda function detects an alarm and calls `CreateEngagement`
2. AWS SDK resolves `ssm-contacts.eu-west-2.amazonaws.com`
3. Private DNS routes the request to the endpoint's private IP (`10.x.x.x`)
4. Request goes through VPC Endpoint → AWS PrivateLink
5. Incident Manager notifies on-call contacts (SMS / email / voice)
6. No NAT, no IGW, no public IP needed ✅

---

## 📋 Prerequisites

| Requirement | Details |
|-------------|---------|
| **IAM Permissions** | Resource needs `ssm-contacts:*` (or scoped permissions) on its role |
| **Security Group** | Resource must allow outbound HTTPS (443) to VPC CIDR |
| **Network** | Resource must be in same VPC as this endpoint |
| **DNS** | VPC must have `enableDnsHostnames` and `enableDnsSupport` set to `true` |

### IAM Policy Example (Least Privilege)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm-contacts:ListContacts",
        "ssm-contacts:GetContact",
        "ssm-contacts:CreateEngagement",
        "ssm-contacts:StopEngagement",
        "ssm-contacts:AcceptPage"
      ],
      "Resource": "*"
    }
  ]
}
```

---

## 🚀 Usage

### Basic Example

```hcl
module "ssm_contacts_endpoint" {
  source = "../../vpc_endpoints/system_manager_contacts"

  env        = "staging"
  project_id = "myapp"

  subnet_ids = [
    "subnet-abc123",
    "subnet-def456"
  ]

  resources_security_group_ids = [
    module.ec2_instance.security_group_id,
    module.lambda.security_group_id
  ]

  enable_ssm_contacts_endpoint = true
}
```

### With Other VPC Endpoints (Recommended)

When using Incident Manager from private subnets, you often also need:

```hcl
# SSM Contacts – Incident Manager API
module "ssm_contacts_endpoint" {
  source = "../../vpc_endpoints/system_manager_contacts"
  # ...
  enable_ssm_contacts_endpoint = true
}

# Secrets Manager – if automation fetches secrets
module "secretsmanager_endpoint" {
  source = "../../vpc_endpoints/secret_manager_endpoint"
  # ...
  enable_secretsmanager_endpoint = true
}

# SNS – if you also publish to SNS during incidents
# (requires NAT or SNS interface endpoint)
```

---

## 📥 Inputs

| Variable | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| `env` | `string` | ✅ | — | Environment name (`staging`, `production`) |
| `project_id` | `string` | ✅ | — | Project identifier for naming and tagging |
| `subnet_ids` | `list(string)` | ✅ | — | Subnet IDs where endpoint ENI is placed |
| `resources_security_group_ids` | `list(string)` | ✅ | — | SG IDs allowed to call the endpoint |
| `enable_ssm_contacts_endpoint` | `bool` | ❌ | `false` | Toggle to create the endpoint |

---

## 📤 Outputs

| Output | Description |
|--------|-------------|
| `ssm_contacts_endpoint.enabled` | Whether the endpoint was created |
| `ssm_contacts_endpoint.endpoint.endpoint_id` | VPC Endpoint ID |
| `ssm_contacts_endpoint.endpoint.endpoint_arn` | VPC Endpoint ARN |
| `ssm_contacts_endpoint.endpoint.service_name` | Full AWS service name |
| `ssm_contacts_endpoint.endpoint.dns_entries` | Private DNS entries for the endpoint |
| `ssm_contacts_endpoint.network.vpc_id` | VPC ID the endpoint belongs to |
| `ssm_contacts_endpoint.network.security_group_ids` | Endpoint security group IDs |
| `ssm_contacts_endpoint.cost.monthly_estimate` | Estimated monthly cost |

---

## 🔐 Security Design

### Security Group Rules

```
Inbound (Ingress):
  Port 443/TCP  ← from var.resources_security_group_ids
  (Only HTTPS, only from trusted resource SGs)

Outbound (Egress):
  All protocols → VPC CIDR only
  (Return traffic stays inside VPC, no internet access)
```

### Network Isolation

- ✅ No public IP required on resources
- ✅ No NAT Gateway needed
- ✅ No Internet Gateway needed
- ✅ Traffic never leaves AWS private network
- ✅ Full CloudTrail audit for all API calls

---

## 🔗 Related Modules

| Module | Endpoint | Use Case |
|--------|----------|----------|
| `session_manager_endpoint` | `ssm`, `ssmmessages`, `ec2messages` | Session Manager (SSH-less access) |
| `secret_manager_endpoint` | `secretsmanager` | Fetch secrets from Secrets Manager |
| `s3_endpoint` | `s3` (Interface) | S3 access from private subnets |
| **`system_manager_contacts`** | `ssm-contacts` | **Incident Manager Contacts (this module)** |

> ⚠️ **Note:** `ssm-contacts` is **separate** from the `ssm`, `ssmmessages`, and `ec2messages` endpoints used by Session Manager. You need all four if you want both Session Manager and Incident Manager Contacts in private subnets.

---

## 🛠️ Common Operations

### List contacts via CLI (from EC2 in private subnet)

```bash
aws ssm-contacts list-contacts --region eu-west-2
```

### Create an engagement (trigger incident notification)

```bash
aws ssm-contacts start-engagement \
  --contact-id "arn:aws:ssm-contacts:eu-west-2:123456789012:contact/on-call-engineer" \
  --sender "MyAutomation" \
  --subject "Production Outage" \
  --content "CPU spike detected on prod-api-01" \
  --region eu-west-2
```

### Python (boto3)

```python
import boto3

client = boto3.client('ssm-contacts', region_name='eu-west-2')

# List all contacts
contacts = client.list_contacts()
print(contacts['Contacts'])

# Create engagement
client.start_engagement(
    ContactId='arn:aws:ssm-contacts:eu-west-2:123456789012:contact/on-call-engineer',
    Sender='Automation',
    Subject='Disk Full on db-01',
    Content='Disk usage exceeded 90% on db-01. Immediate action required.',
)
```

### Node.js (AWS SDK v3)

```javascript
const { SSMContactsClient, ListContactsCommand } = require('@aws-sdk/client-ssm-contacts');

const client = new SSMContactsClient({ region: 'eu-west-2' });
const response = await client.send(new ListContactsCommand({}));
console.log(response.Contacts);
```

