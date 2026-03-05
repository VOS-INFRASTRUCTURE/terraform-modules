################################################################################
# OUTPUTS - Endpoint Information and Configuration
################################################################################

output "ecr_endpoints" {
  description = "ECR (Docker Registry) VPC Interface Endpoints configuration and identifiers"
  value = {
    # Feature toggle status
    enabled = var.enable_ecr_endpoints

    # ECR API Endpoint (control plane)
    ecr_api = {
      endpoint_id         = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_api[0].id : null
      endpoint_arn        = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_api[0].arn : null
      service_name        = local.ecr_api_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_api[0].dns_entry : []
      purpose             = "ECR control plane: auth tokens, image metadata, repository management"
    }

    # ECR DKR Endpoint (Docker Registry protocol)
    ecr_dkr = {
      endpoint_id         = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_dkr[0].id : null
      endpoint_arn        = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_dkr[0].arn : null
      service_name        = local.ecr_dkr_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_ecr_endpoints ? aws_vpc_endpoint.ecr_dkr[0].dns_entry : []
      purpose             = "Docker Registry v2 protocol: image pull/push, manifest fetching"
    }

    # S3 Interface Endpoint (ECR layer storage)
    s3_interface = {
      endpoint_id         = var.enable_ecr_endpoints && var.create_s3_endpoint ? aws_vpc_endpoint.s3[0].id : null
      endpoint_arn        = var.enable_ecr_endpoints && var.create_s3_endpoint ? aws_vpc_endpoint.s3[0].arn : null
      service_name        = local.s3_service_name
      private_dns_enabled = true
      dns_entries         = var.enable_ecr_endpoints && var.create_s3_endpoint ? aws_vpc_endpoint.s3[0].dns_entry : []
      created             = var.create_s3_endpoint
      purpose             = "S3 Interface: private access to ECR image layers stored in S3"
    }

    # Network configuration
    network = {
      vpc_id             = local.vpc_id
      subnet_ids         = local.subnet_ids
      security_group_ids = local.endpoint_sg_ids
      vpc_cidr_block     = local.vpc_cidr_block
    }

    # Cost information
    cost = {
      monthly_estimate = var.enable_ecr_endpoints ? (
        var.create_s3_endpoint
        ? "~$21.60 USD (3 endpoints × $7.20/month) + minimal data transfer (~$0.01/GB)"
        : "~$14.40 USD (2 endpoints × $7.20/month) + minimal data transfer (~$0.01/GB)"
      ) : "$0 (endpoints disabled)"
      comparison = "NAT Gateway alternative: ~$32.40/month + $0.045/GB data transfer"
      savings    = var.enable_ecr_endpoints ? "~$10.80/month vs NAT Gateway (+ lower data transfer costs)" : "N/A"
      note       = "Costs are per AZ. Multi-AZ = multiply by number of subnets/AZs."
    }

    # Usage instructions
    usage = {
      docker_pull_example     = "docker pull {account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/{repo}:{tag}"
      ecr_login_example       = "aws ecr get-login-password --region ${data.aws_region.current.name} | docker login --username AWS --password-stdin {account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
      list_images_example     = "aws ecr list-images --repository-name {repo} --region ${data.aws_region.current.name}"
      ecs_image_format        = "{account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com/{repo}:{tag}"
      requirements = [
        "Resource must be in same VPC as endpoint",
        "Resource security group must allow outbound HTTPS (443) to VPC CIDR",
        "IAM role must have ecr:GetAuthorizationToken + ecr:BatchGetImage + ecr:GetDownloadUrlForLayer",
        "ECS task execution role needs ecr:* permissions for Fargate image pulls",
        "VPC must have DNS hostnames and DNS resolution enabled"
      ]
    }

    # Validation notes
    validation = {
      all_three_required       = "ALL THREE endpoints (ecr.api + ecr.dkr + s3) are required for image pulls to work"
      private_dns_required     = "private_dns_enabled MUST be true on both ECR endpoints for Docker client to work"
      s3_interface_vs_gateway  = "S3 Interface (not Gateway) is required: S3 Gateway lacks private DNS, causing layer downloads to fail in private subnets without NAT"
      no_internet_needed       = "Container image pulls route entirely through VPC endpoints (no NAT/IGW required)"
    }
  }
}

