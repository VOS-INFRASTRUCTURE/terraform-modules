################################################################################
# OUTPUTS - Endpoint Information and Configuration
################################################################################

output "ssm_incidents_endpoint" {
  description = "SSM Incidents (Incident Manager) VPC Interface Endpoint configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = var.enable_ssm_incidents_endpoint

    # SSM Incidents Endpoint details
    endpoint = {
      endpoint_id         = var.enable_ssm_incidents_endpoint ? aws_vpc_endpoint.ssm_incidents[0].id : null
      endpoint_arn        = var.enable_ssm_incidents_endpoint ? aws_vpc_endpoint.ssm_incidents[0].arn : null
      service_name        = local.ssm_incidents_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_ssm_incidents_endpoint ? aws_vpc_endpoint.ssm_incidents[0].dns_entry : []
    }

    # Network configuration
    network = {
      vpc_id             = local.ssm_incidents_vpc_id
      subnet_ids         = local.ssm_incidents_subnet_ids
      security_group_ids = local.ssm_incidents_sg_ids
      vpc_cidr_block     = local.vpc_cidr_block
    }

    # Cost information
    cost = {
      monthly_estimate = var.enable_ssm_incidents_endpoint ? "~$7.20 USD (1 Interface endpoint × $7.20/month) + minimal data transfer (~$0.01/GB)" : "$0 (endpoint disabled)"
      comparison       = "NAT Gateway alternative: ~$32.40/month + $0.045/GB data transfer"
      savings          = var.enable_ssm_incidents_endpoint ? "~$25.20/month + reduced data transfer costs" : "N/A"
    }

    # Usage instructions
    usage = {
      aws_cli_example = "aws ssm-incidents list-incident-records --region ${data.aws_region.current.name}"
      python_example  = "boto3.client('ssm-incidents').list_incident_records()"
      nodejs_example  = "new AWS.SSMIncidents().listIncidentRecords({}).promise()"
      requirements = [
        "Resource must be in same VPC as endpoint",
        "Resource security group must allow outbound HTTPS (443) to VPC CIDR",
        "IAM role/user must have ssm-incidents:* permissions as needed",
        "Private DNS enabled on endpoint (automatically resolves ssm-incidents.{region}.amazonaws.com)"
      ]
    }

    # Validation notes
    validation = {
      private_dns_required = "private_dns_enabled MUST be true for standard AWS SDK calls to work"
      security_groups      = "Resources must allow outbound 443; Endpoint must allow inbound 443 from resources"
      no_internet_needed   = "All SSM Incidents API calls route through private VPC endpoint (no NAT/IGW required)"
      related_endpoints    = "ssm-contacts endpoint handles on-call contact management; this endpoint handles incident records"
    }
  }
}

