################################################################################
# AWS SSM CONTACTS (INCIDENT MANAGER) VPC ENDPOINT
#
# Purpose: Enables private access to AWS Systems Manager Incident Manager
#          Contacts API from EC2 instances in private subnets without NAT
#          Gateway or internet access.
#
# What is SSM Contacts / Incident Manager:
# AWS Systems Manager Incident Manager is an incident management console
# that helps you prepare for and respond to operational incidents. The
# Contacts (ssm-contacts) API manages on-call schedules, escalation plans,
# and contact channels (email, SMS, voice) for incident response.
#
# Common API Operations via this endpoint:
# - ssm-contacts:CreateContact       - Define responders and their channels
# - ssm-contacts:CreateEngagement    - Notify contacts about an incident
# - ssm-contacts:ListContacts        - List all defined contacts
# - ssm-contacts:GetContact          - Retrieve a specific contact
# - ssm-contacts:CreateRotation      - Define on-call rotation schedules
# - ssm-contacts:ListRotations       - List rotation schedules
# - ssm-contacts:StartEngagement     - Begin engaging a contact plan
# - ssm-contacts:StopEngagement      - Stop an active engagement
# - ssm-contacts:AcceptPage          - Acknowledge an incident page
#
# Why Use VPC Endpoint for SSM Contacts:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. Lambda / EC2 triggers incident response (CreateEngagement)           │
# │ 2. Without VPC endpoint: Requires NAT Gateway or internet access        │
# │ 3. With VPC endpoint: Traffic stays private within AWS network          │
# │ 4. SSM Contacts API calls route through private VPC endpoint            │
# │ 5. More secure + cost-effective (saves NAT Gateway costs)               │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Network Flow:
#   EC2 / Lambda (Private Subnet) → VPC Endpoint → SSM Contacts Service
#                  ↓
#   No NAT, No IGW, No Public IP needed!
#
# Cost Comparison (per month, per AZ):
# ┌────────────────────────────┬──────────┬────────────────────────┐
# │ Solution                   │ Cost     │ Notes                  │
# ├────────────────────────────┼──────────┼────────────────────────┤
# │ NAT Gateway                │ ~$32.40  │ + data transfer fees   │
# │ SSM Contacts Endpoint      │ ~$7.20   │ + minimal data transfer│
# │ Savings                    │ ~$25.20  │ + better security      │
# └────────────────────────────┴──────────┴────────────────────────┘
#
# Relation to Other Endpoints:
# SSM Contacts is a separate endpoint from the core SSM endpoints.
# For full Session Manager support you also need:
#   - com.amazonaws.{region}.ssm            (Systems Manager agent)
#   - com.amazonaws.{region}.ssmmessages    (Session Manager channels)
#   - com.amazonaws.{region}.ec2messages    (EC2 message delivery)
# This module handles ONLY the Incident Manager Contacts endpoint.
#
# Security Benefits:
# ✅ No internet gateway or NAT required
# ✅ All traffic stays within AWS network
# ✅ Incident API calls never traverse the public internet
# ✅ Full audit trail via CloudTrail
# ✅ Private DNS resolution for seamless AWS SDK integration
#
# When to Use This Module:
# ✅ Lambda or EC2 in private subnets needs to trigger incident engagements
# ✅ Automation scripts manage on-call rotations or escalation plans
# ✅ Security/compliance requires no internet access from workloads
# ✅ Want to avoid NAT Gateway costs for Incident Manager traffic
#
# When NOT to Use:
# ❌ Already have NAT Gateway used for other services (no cost benefit)
# ❌ EC2 instances have public IPs with internet gateway
# ❌ SSM Contacts is used very infrequently (cost may not justify endpoint)
################################################################################

################################################################################
# LOCALS - Computed Values
################################################################################

locals {
  # SSM Contacts service name for the current region
  # AWS-managed service endpoint following standard naming pattern
  ssm_contacts_service_name = "com.amazonaws.${data.aws_region.current.name}.ssm-contacts"

  # VPC ID discovered from provided subnet
  # Only computed when endpoint is enabled to avoid unnecessary data lookups
  ssm_contacts_vpc_id = var.enable_ssm_contacts_endpoint ? data.aws_subnet.any_subnet.vpc_id : ""

  # Subnet IDs where endpoint ENI will be created
  # Same subnets as the compute resources that need SSM Contacts access
  ssm_contacts_subnet_ids = var.enable_ssm_contacts_endpoint ? var.subnet_ids : []

  # Security group for the VPC endpoint
  # Allows inbound HTTPS (443) from allowed resource security groups
  ssm_contacts_sg_ids = var.enable_ssm_contacts_endpoint ? [aws_security_group.endpoints_sg[0].id] : []

  # VPC CIDR block for endpoint security group egress rules
  # Restricts outbound traffic to stay within VPC only
  vpc_cidr_block = var.enable_ssm_contacts_endpoint ? data.aws_vpc.target_vpc.cidr_block : ""
}

################################################################################
# VPC INTERFACE ENDPOINT FOR SSM CONTACTS
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
# 1. Your code calls: ssmcontacts.list_contacts()
# 2. AWS SDK resolves: ssm-contacts.{region}.amazonaws.com
# 3. Private DNS routes to endpoint's private IP (10.x.x.x)
# 4. Request goes through VPC endpoint (no internet needed)
# 5. SSM Contacts returns the response
################################################################################

# SSM Contacts VPC Interface Endpoint
# Purpose: Private access to AWS Incident Manager Contacts API
resource "aws_vpc_endpoint" "ssm_contacts" {
  count = var.enable_ssm_contacts_endpoint ? 1 : 0

  vpc_id            = local.ssm_contacts_vpc_id
  service_name      = local.ssm_contacts_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.ssm_contacts_subnet_ids
  security_group_ids = local.ssm_contacts_sg_ids

  # CRITICAL: Private DNS must be enabled
  # This allows standard AWS SDK calls to work without code changes
  # ssm-contacts.{region}.amazonaws.com → private IP (10.x.x.x)
  # Without this, you'd need to use endpoint-specific DNS names
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-ssm-contacts-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "SSMContacts-VPC-Endpoint"
    Service     = "SSMContacts"
  }
}

