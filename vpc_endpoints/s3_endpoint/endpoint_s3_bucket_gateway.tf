################################################################################
# S3 GATEWAY VPC ENDPOINT
#
# Purpose: Allows resources in private subnets to access S3 directly
#          without NAT Gateway or internet access - COMPLETELY FREE!
#
# How Gateway Endpoint Works:
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ 1. Adds S3 prefix list route to your route tables                       │
# │ 2. Traffic destined for S3 is routed through the Gateway endpoint       │
# │ 3. Traffic stays within AWS network (never touches internet)            │
# │ 4. No hourly charges, no data transfer fees                             │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Gateway vs Interface Endpoint:
# ┌──────────────────┬─────────────────┬────────────────────────┐
# │ Feature          │ Gateway         │ Interface              │
# ├──────────────────┼─────────────────┼────────────────────────┤
# │ Cost             │ FREE            │ ~$7.20/month per AZ   │
# │ Works via        │ Route tables    │ ENI in subnet          │
# │ Endpoint policy  │ ✅ Yes          │ ❌ No                  │
# │ Private DNS      │ ❌ No           │ ✅ Yes                 │
# │ Security groups  │ ❌ No           │ ✅ Yes                 │
# │ Recommended      │ ✅ Default      │ Special cases only     │
# └──────────────────┴─────────────────┴────────────────────────┘
#
# When to Use Gateway Endpoint:
# ✅ Default choice for most use cases
# ✅ EC2 instances in private subnets
# ✅ Lambda functions (with VPC)
# ✅ ECS tasks
# ✅ Want FREE S3 access without NAT
# ✅ Need endpoint policies for security
#
# Cost Savings:
# - Gateway endpoint: FREE (no charges)
# - NAT Gateway avoided: ~$32.40/month + data transfer fees
# - Total savings: ~$32.40+/month
#
# Security:
# - Endpoint policy restricts access to specific S3 buckets
# - Traffic never leaves AWS network
# - No public IP exposure
# - Full CloudTrail audit trail
################################################################################
################################################################################
# S3 GATEWAY VPC ENDPOINT
#
# Type: Gateway (NOT Interface)
# - Adds route to S3 in route tables
# - Completely FREE (no hourly charges)
# - Supports endpoint policies
# - Recommended for most use cases
################################################################################
resource "aws_vpc_endpoint" "s3_gateway" {
  count = local.create_gateway_endpoint || local.create_interface_endpoint ? 1 : 0
  vpc_id            = data.aws_vpc.target_vpc.id
  service_name      = local.s3_service_name
  vpc_endpoint_type = "Gateway"
  # Route table IDs to associate with this endpoint
  # Traffic from these route tables to S3 will use this endpoint
  route_table_ids = local.route_table_ids
  # Endpoint policy: Restrict access to specific S3 buckets
  # This prevents resources from accessing unauthorized buckets
  # If no buckets specified, allows access to all S3 buckets
  policy = local.s3_endpoint_policy
  # NOTE: private_dns_enabled is not supported for Gateway endpoints
  # Gateway endpoints work via route table modifications, not DNS
  tags = {
    Name        = "${var.env}-${var.project_id}-${data.aws_vpc.target_vpc.id}-s3-gateway-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-GatewayEndpoint"
    Type        = "Gateway"
    Cost        = "FREE"
  }
}
################################################################################
# OUTPUT - Gateway Endpoint Information
################################################################################
output "s3_gateway_endpoint" {
  description = "S3 Gateway VPC Endpoint configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = local.create_gateway_endpoint
    # Endpoint details
    endpoint = {
      endpoint_id   = local.create_gateway_endpoint ? aws_vpc_endpoint.s3_gateway[0].id : null
      endpoint_arn  = local.create_gateway_endpoint ? aws_vpc_endpoint.s3_gateway[0].arn : null
      service_name  = local.s3_service_name
      endpoint_type = "Gateway"
      state         = local.create_gateway_endpoint ? aws_vpc_endpoint.s3_gateway[0].state : null
    }
    # Network configuration
    network = {
      vpc_id                  = data.aws_vpc.target_vpc.id
      associated_route_tables = local.route_table_ids
    }
    # Policy configuration
    policy = {
      restricted_buckets = var.s3_bucket_arns
      policy_type        = length(var.s3_bucket_arns) > 0 ? "Restricted to specific buckets" : "Allow all S3 buckets"
    }
    # Cost information
    cost = {
      monthly_estimate  = "FREE (Gateway endpoint has no hourly charge)"
      data_transfer     = "FREE (S3 data transfer in same region is FREE)"
      nat_gateway_saved = "~$32.40/month + $0.045/GB data transfer"
      total_savings     = "~$32.40+/month"
    }
    # Usage instructions
    usage = {
      aws_cli_example    = "aws s3 ls s3://your-bucket/ --region ${data.aws_region.current.name}"
      python_example     = "boto3.client('s3').list_objects_v2(Bucket='your-bucket')"
      terraform_example  = "aws_s3_bucket.example.id"
      requirements       = [
        "Resource must be in VPC with route table associated to this endpoint",
        "IAM role/user must have s3:* permissions for target buckets",
        "Bucket must be in same region or policy allows cross-region access"
      ]
    }
  }
}
