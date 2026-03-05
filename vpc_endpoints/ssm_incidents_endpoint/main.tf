################################################################################
# AWS SSM INCIDENTS (INCIDENT MANAGER) VPC ENDPOINT
#
# Purpose: Enables private access to AWS Systems Manager Incident Manager
#          Incidents API from EC2 instances, Lambda functions, and ECS tasks
#          in private subnets without NAT Gateway or internet access.
#
# What is SSM Incidents / Incident Manager:
# AWS Systems Manager Incident Manager is an incident management console
# that helps you prepare for and respond to operational incidents.
# The Incidents (ssm-incidents) API manages the full lifecycle of incidents:
#   - Creating and updating incidents
#   - Adding timeline events and related items
#   - Managing incident action items
#   - Defining response plans that automate incident creation
#   - Linking incidents to OpsItems (OpsCenter)
#
# Difference between ssm-contacts and ssm-incidents:
# ┌────────────────────┬──────────────────────────────────────────────────┐
# │ ssm-contacts       │ Who to notify (people, on-call schedules,        │
# │                    │ escalation plans, contact channels)              │
# ├────────────────────┼──────────────────────────────────────────────────┤
# │ ssm-incidents      │ What happened (incident records, timeline,       │
# │                    │ response plans, impact tracking, runbooks)       │
# └────────────────────┴──────────────────────────────────────────────────┘
#
# Common API Operations via this endpoint:
# - ssm-incidents:StartIncident         - Open a new incident
# - ssm-incidents:UpdateIncidentRecord  - Update severity, title, summary
# - ssm-incidents:GetIncidentRecord     - Retrieve incident details
# - ssm-incidents:ListIncidentRecords   - List all incidents
# - ssm-incidents:CreateResponsePlan    - Define automated response plans
# - ssm-incidents:GetResponsePlan       - Retrieve a response plan
# - ssm-incidents:ListResponsePlans     - List all response plans
# - ssm-incidents:CreateTimelineEvent   - Add event to incident timeline
# - ssm-incidents:ListTimelineEvents    - List timeline events
# - ssm-incidents:PutResourcePolicy     - Share across accounts
#
# Why Use VPC Endpoint for SSM Incidents:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. Lambda / EC2 triggers incident via StartIncident                     │
# │ 2. Without VPC endpoint: Requires NAT Gateway or internet access        │
# │ 3. With VPC endpoint: Traffic stays private within AWS network          │
# │ 4. SSM Incidents API calls route through private VPC endpoint           │
# │ 5. More secure + cost-effective (saves NAT Gateway costs)               │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Network Flow:
#   EC2 / Lambda (Private Subnet) → VPC Endpoint → SSM Incidents Service
#                  ↓
#   No NAT, No IGW, No Public IP needed!
#
# Cost Comparison (per month, per AZ):
# ┌────────────────────────────┬──────────┬────────────────────────┐
# │ Solution                   │ Cost     │ Notes                  │
# ├────────────────────────────┼──────────┼────────────────────────┤
# │ NAT Gateway                │ ~$32.40  │ + data transfer fees   │
# │ SSM Incidents Endpoint     │ ~$7.20   │ + minimal data transfer│
# │ Savings                    │ ~$25.20  │ + better security      │
# └────────────────────────────┴──────────┴────────────────────────┘
#
# Relation to Other Endpoints:
# SSM Incidents is separate from SSM Contacts and core SSM endpoints.
# For full Incident Manager support you may also need:
#   - com.amazonaws.{region}.ssm-contacts   (on-call contact management)
# For full Session Manager support you also need:
#   - com.amazonaws.{region}.ssm            (Systems Manager agent)
#   - com.amazonaws.{region}.ssmmessages    (Session Manager channels)
#   - com.amazonaws.{region}.ec2messages    (EC2 message delivery)
# This module handles ONLY the Incident Manager Incidents endpoint.
#
# Security Benefits:
# ✅ No internet gateway or NAT required
# ✅ All traffic stays within AWS network
# ✅ Incident API calls never traverse the public internet
# ✅ Full audit trail via CloudTrail
# ✅ Private DNS resolution for seamless AWS SDK integration
#
# When to Use This Module:
# ✅ Lambda or EC2 in private subnets needs to create or update incidents
# ✅ Automation scripts manage response plans or timeline events
# ✅ Security/compliance requires no internet access from workloads
# ✅ Want to avoid NAT Gateway costs for Incident Manager traffic
#
# When NOT to Use:
# ❌ Already have NAT Gateway used for other services (no cost benefit)
# ❌ EC2 instances have public IPs with internet gateway
# ❌ SSM Incidents is used very infrequently (cost may not justify endpoint)
################################################################################

################################################################################
# LOCALS - Computed Values
################################################################################

locals {
  # SSM Incidents service name for the current region
  # AWS-managed service endpoint following standard naming pattern
  ssm_incidents_service_name = "com.amazonaws.${data.aws_region.current.name}.ssm-incidents"

  # VPC ID discovered from provided subnet
  # Only computed when endpoint is enabled to avoid unnecessary data lookups
  ssm_incidents_vpc_id = var.enable_ssm_incidents_endpoint ? data.aws_subnet.any_subnet.vpc_id : ""

  # Subnet IDs where endpoint ENI will be created
  # Same subnets as the compute resources that need SSM Incidents access
  ssm_incidents_subnet_ids = var.enable_ssm_incidents_endpoint ? var.subnet_ids : []

  # Security group for the VPC endpoint
  # Allows inbound HTTPS (443) from allowed resource security groups
  ssm_incidents_sg_ids = var.enable_ssm_incidents_endpoint ? [aws_security_group.endpoints_sg[0].id] : []

  # VPC CIDR block for endpoint security group egress rules
  # Restricts outbound traffic to stay within VPC only
  vpc_cidr_block = var.enable_ssm_incidents_endpoint ? data.aws_vpc.target_vpc.cidr_block : ""
}

################################################################################
# VPC INTERFACE ENDPOINT FOR SSM INCIDENTS
#
# Endpoint Type: Interface (NOT Gateway)
# - Creates ENI (Elastic Network Interface) in each specified subnet
# - Provides private IP addresses within your VPC
# - Requires private DNS enabled for seamless AWS SDK calls
#
# Key Requirements:
# ✅ private_dns_enabled = true (mandatory for standard AWS SDK calls)
# ✅ Security group must allow HTTPS (443) inbound from resources
# ✅ Resource security group must allow HTTPS (443) outbound
#
# How It Works:
# 1. Your code calls: client.start_incident(responsePlanArn=...)
# 2. AWS SDK resolves: ssm-incidents.{region}.amazonaws.com
# 3. Private DNS routes to endpoint's private IP (10.x.x.x)
# 4. Request goes through VPC endpoint (no internet needed)
# 5. SSM Incidents creates the incident record and returns details
################################################################################

# SSM Incidents VPC Interface Endpoint
# Purpose: Private access to AWS Incident Manager Incidents API
resource "aws_vpc_endpoint" "ssm_incidents" {
  count = var.enable_ssm_incidents_endpoint ? 1 : 0

  vpc_id            = local.ssm_incidents_vpc_id
  service_name      = local.ssm_incidents_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.ssm_incidents_subnet_ids
  security_group_ids = local.ssm_incidents_sg_ids

  # CRITICAL: Private DNS must be enabled
  # This allows standard AWS SDK calls to work without code changes
  # ssm-incidents.{region}.amazonaws.com → private IP (10.x.x.x)
  # Without this, you'd need to use endpoint-specific DNS names
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-ssm-incidents-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SSMIncidents-VPC-Endpoint"
    Service     = "SSMIncidents"
  }
}

