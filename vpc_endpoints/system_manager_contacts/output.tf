################################################################################
# OUTPUTS - Endpoint Information and Configuration
################################################################################

output "ssm_contacts_endpoint" {
  description = "SSM Contacts (Incident Manager) VPC Interface Endpoint configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = var.enable_ssm_contacts_endpoint

    # SSM Contacts Endpoint details
    endpoint = {
      endpoint_id         = var.enable_ssm_contacts_endpoint ? aws_vpc_endpoint.ssm_contacts[0].id : null
      endpoint_arn        = var.enable_ssm_contacts_endpoint ? aws_vpc_endpoint.ssm_contacts[0].arn : null
      service_name        = local.ssm_contacts_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_ssm_contacts_endpoint ? aws_vpc_endpoint.ssm_contacts[0].dns_entry : []
    }

    # Network configuration
    network = {
      vpc_id             = local.ssm_contacts_vpc_id
      subnet_ids         = local.ssm_contacts_subnet_ids
      security_group_ids = local.ssm_contacts_sg_ids
      vpc_cidr_block     = local.vpc_cidr_block
    }

    # Cost information
    cost = {
      monthly_estimate = var.enable_ssm_contacts_endpoint ? "~$7.20 USD (1 Interface endpoint × $7.20/month) + minimal data transfer (~$0.01/GB)" : "$0 (endpoint disabled)"
      comparison       = "NAT Gateway alternative: ~$32.40/month + $0.045/GB data transfer"
      savings          = var.enable_ssm_contacts_endpoint ? "~$25.20/month + reduced data transfer costs" : "N/A"
    }

    # Usage instructions
    usage = {
      aws_cli_example = "aws ssm-contacts list-contacts --region ${data.aws_region.current.name}"
      python_example  = "boto3.client('ssm-contacts').list_contacts()"
      nodejs_example  = "new AWS.SSMContacts().listContacts({}).promise()"
      requirements = [
        "Resource must be in same VPC as endpoint",
        "Resource security group must allow outbound HTTPS (443) to VPC CIDR",
        "IAM role/user must have ssm-contacts:* permissions as needed",
        "Private DNS enabled on endpoint (automatically resolves ssm-contacts.{region}.amazonaws.com)"
      ]
    }

    # Validation notes
    validation = {
      private_dns_required = "private_dns_enabled MUST be true for standard AWS SDK calls to work"
      security_groups      = "Resources must allow outbound 443, Endpoint must allow inbound 443 from resources"
      no_internet_needed   = "All SSM Contacts API calls route through private VPC endpoint (no NAT/IGW required)"
      note                 = "This endpoint is separate from SSM, SSMMessages, and EC2Messages endpoints (Session Manager)"
    }
  }
}

