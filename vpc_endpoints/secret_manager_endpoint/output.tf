################################################################################
# OUTPUTS - Endpoint Information and Configuration
################################################################################
output "secretsmanager_endpoint" {
  description = "Secrets Manager VPC Interface Endpoint configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = var.enable_secretsmanager_endpoint
    # Secrets Manager Endpoint details
    endpoint = {
      endpoint_id         = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].id : null
      endpoint_arn        = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].arn : null
      service_name        = local.secretsmanager_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_secretsmanager_endpoint ? aws_vpc_endpoint.secretsmanager[0].dns_entry : []
    }
    # Network configuration
    network = {
      vpc_id             = local.secretsmanager_vpc_id
      subnet_ids         = local.secretsmanager_subnet_ids
      security_group_ids = local.secretsmanager_sg_ids
      vpc_cidr_block     = local.vpc_cidr_block
    }
    # Cost information
    cost = {
      monthly_estimate = var.enable_secretsmanager_endpoint ? "~$7.20 USD (1 Interface endpoint × $7.20/month) + minimal data transfer (~$0.01/GB)" : "$0 (endpoint disabled)"
      comparison       = "NAT Gateway alternative: ~$32.40/month + $0.045/GB data transfer"
      savings          = var.enable_secretsmanager_endpoint ? "~$25.20/month + reduced data transfer costs" : "N/A"
    }
    # Usage instructions
    usage = {
      aws_cli_example = "aws secretsmanager get-secret-value --secret-id my-database-password"
      python_example  = "boto3.client('secretsmanager').get_secret_value(SecretId='my-secret')"
      nodejs_example  = "new AWS.SecretsManager().getSecretValue({SecretId: 'my-secret'})"
      requirements = [
        "Resource must be in same VPC as endpoint",
        "Resource security group must allow outbound HTTPS (443) to VPC CIDR",
        "IAM role/user must have secretsmanager:GetSecretValue permission",
        "Private DNS enabled on endpoint (automatically resolves secretsmanager.{region}.amazonaws.com)"
      ]
    }
    # Validation notes
    validation = {
      private_dns_required = "private_dns_enabled MUST be true for standard AWS SDK calls to work"
      security_groups      = "Resources must allow outbound 443, Endpoint must allow inbound 443 from resources"
      no_internet_needed   = "All Secrets Manager API calls route through private VPC endpoint (no NAT/IGW required)"
    }
  }
}
