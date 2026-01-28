################################################################################
# OUTPUTS - Endpoint Information and Configuration
################################################################################
output "session_manager_endpoints" {
  description = "Session Manager VPC Interface Endpoints configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = var.enable_session_manager_endpoints
    # Endpoint 1: SSM (Systems Manager API)
    ssm = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].arn : null
      service_name        = local.ssm_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssm[0].dns_entry : []
    }
    # Endpoint 2: SSM Messages (Session Manager messaging)
    ssmmessages = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].arn : null
      service_name        = local.ssmmessages_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ssmmessages[0].dns_entry : []
    }
    # Endpoint 3: EC2 Messages (EC2 communication)
    ec2messages = {
      endpoint_id         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].id : null
      endpoint_arn        = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].arn : null
      service_name        = local.ec2messages_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_session_manager_endpoints ? aws_vpc_endpoint.ec2messages[0].dns_entry : []
    }
    # Network configuration
    network = {
      vpc_id             = local.ssm_vpc_id
      subnet_ids         = local.ssm_subnet_ids
      security_group_ids = local.ssm_sg_ids
      vpc_cidr_block     = local.vpc_cidr_block
    }
    # Cost information
    cost = {
      monthly_estimate = var.enable_session_manager_endpoints ? "~$21.60 USD (3 Interface endpoints × $7.20/month each) + minimal data transfer (~$0.01/GB)" : "$0 (endpoints disabled)"
      comparison       = "NAT Gateway alternative: ~$32.40/month + $0.045/GB data transfer"
      savings          = var.enable_session_manager_endpoints ? "~$10.80/month + reduced data transfer costs" : "N/A"
    }
    # Usage instructions
    usage = {
      connect_command = "aws ssm start-session --target <instance-id>"
      requirements = [
        "EC2 instance must have SSM Agent installed (pre-installed on Amazon Linux 2, Ubuntu 20.04+)",
        "EC2 instance must have IAM role with AmazonSSMManagedInstanceCore policy",
        "EC2 security group must allow outbound HTTPS (443) to VPC CIDR",
        "User must have IAM permissions: ssm:StartSession, ssm:TerminateSession"
      ]
    }
    # Validation reminder
    validation = {
      all_three_required = "⚠️ ALL THREE endpoints (ssm, ssmmessages, ec2messages) are MANDATORY"
      missing_any        = "Missing even ONE endpoint will break Session Manager completely!"
      private_dns        = "private_dns_enabled MUST be true on all endpoints"
      security_groups    = "EC2 must allow outbound 443, Endpoint must allow inbound 443 from EC2"
    }
  }
}
