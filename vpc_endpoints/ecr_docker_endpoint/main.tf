################################################################################
# AWS ECR (DOCKER REGISTRY) VPC ENDPOINTS
#
# Purpose: Enables private access to Amazon ECR (Elastic Container Registry)
#          from ECS tasks, EC2 instances, and Lambda in private subnets without
#          NAT Gateway or internet access.
#
# What is Amazon ECR:
# Amazon Elastic Container Registry (ECR) is a fully managed Docker container
# registry that makes it easy to store, manage, and deploy container images.
# When running containers in private subnets (ECS Fargate, ECS EC2, or EC2),
# the container runtime needs to pull images from ECR.
#
# Why THREE Endpoints are Required:
# ┌────────────────────────────────────────────────────────────────────────┐
# │ 1. ecr.api  → ECR control plane (auth tokens, image metadata)         │
# │ 2. ecr.dkr  → Docker Registry protocol (actual layer download)        │
# │ 3. s3       → S3 Interface (ECR stores image layers in S3)            │
# │                                                                        │
# │ ⚠️  Missing ANY one = image pulls will FAIL in private subnets         │
# └────────────────────────────────────────────────────────────────────────┘
#
# Docker Pull Flow (what happens behind the scenes):
# ┌─────────────────────────────────────────────────────────────────────────┐
# │ Step 1: Get auth token  → ecr.api endpoint                             │
# │   aws ecr get-login-password                                            │
# │   POST ecr.{region}.amazonaws.com/authorization                         │
# │                                                                         │
# │ Step 2: Authenticate    → ecr.dkr endpoint                             │
# │   docker login {account}.dkr.ecr.{region}.amazonaws.com                │
# │   GET {account}.dkr.ecr.{region}.amazonaws.com/v2/                      │
# │                                                                         │
# │ Step 3: Pull manifest   → ecr.dkr endpoint                             │
# │   GET /v2/{repo}/manifests/{tag}                                        │
# │                                                                         │
# │ Step 4: Pull layers     → S3 Interface endpoint                        │
# │   ECR stores image layers in S3. Each layer = GET request to S3.       │
# │   Without S3 endpoint: layer downloads FAIL (no internet access)       │
# └─────────────────────────────────────────────────────────────────────────┘
#
# Cost Comparison (per month, per AZ):
# ┌────────────────────────────────┬──────────┬──────────────────────────┐
# │ Solution                       │ Cost     │ Notes                    │
# ├────────────────────────────────┼──────────┼──────────────────────────┤
# │ NAT Gateway                    │ ~$32.40  │ + data transfer $0.045/GB│
# │ 3 ECR Interface Endpoints      │ ~$21.60  │ + data transfer $0.01/GB │
# │ Savings                        │ ~$10.80  │ + better security        │
# └────────────────────────────────┴──────────┴──────────────────────────┘
#
# Note on S3 Endpoint for ECR:
# ECR image layers are stored in S3. In private subnets, you need either:
#   a) S3 Interface Endpoint (this module creates this - always works)
#   b) S3 Gateway Endpoint (cheaper, but requires correct DNS setup)
# This module uses S3 Interface endpoint for reliability.
# If you already have an S3 Interface Endpoint in your VPC, set:
#   create_s3_endpoint = false  and pass  existing_s3_endpoint_id
#
# Security Benefits:
# ✅ No internet gateway or NAT required for image pulls
# ✅ ECR traffic stays within AWS private network
# ✅ Image layers (stored in S3) served via private endpoint
# ✅ Full audit trail via CloudTrail
# ✅ Private DNS resolution - no code changes needed
# ✅ Works with ECS Fargate, ECS EC2, EC2 with Docker, Lambda (container images)
#
# When to Use This Module:
# ✅ ECS Fargate tasks in private subnets pulling images from ECR
# ✅ EC2 instances with Docker in private subnets
# ✅ Lambda container image functions in private subnets
# ✅ CodeBuild projects pulling ECR images
# ✅ Security/compliance requires no internet access
#
# When NOT to Use:
# ❌ Already have NAT Gateway for other reasons (no cost benefit)
# ❌ ECS tasks are in public subnets with public IP assignment
# ❌ Using Docker Hub or other public registries (ECR endpoint won't help)
################################################################################

################################################################################
# LOCALS - Computed Values
################################################################################

locals {
  # ECR service names for the current region
  # AWS-managed service endpoints following standard naming pattern
  ecr_api_service_name = "com.amazonaws.${data.aws_region.current.name}.ecr.api"
  ecr_dkr_service_name = "com.amazonaws.${data.aws_region.current.name}.ecr.dkr"
  s3_service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"

  # VPC ID discovered from provided subnet
  vpc_id = data.aws_subnet.any_subnet.vpc_id

  # Subnet IDs where endpoint ENIs will be created
  # Same subnets as the ECS tasks / EC2 instances pulling images
  subnet_ids = var.enable_ecr_endpoints ? var.subnet_ids : []

  # Security group for the Interface endpoints (ecr.api and ecr.dkr)
  # S3 Interface endpoint also uses this security group
  endpoint_sg_ids = var.enable_ecr_endpoints ? [aws_security_group.endpoints_sg[0].id] : []

  # VPC CIDR block for security group egress rules
  vpc_cidr_block = var.enable_ecr_endpoints ? data.aws_vpc.target_vpc.cidr_block : ""
}

################################################################################
# ENDPOINT 1: ECR API
#
# Purpose: ECR control plane communications
# - GetAuthorizationToken   (docker login / aws ecr get-login-password)
# - DescribeRepositories    (list repositories)
# - DescribeImages          (list images and tags)
# - BatchGetImage           (image manifest fetching)
# - InitiateLayerUpload     (push operations)
# - BatchCheckLayerAvailability
#
# Type: Interface
# Private DNS: REQUIRED (ecr.{region}.amazonaws.com → private IP)
################################################################################

resource "aws_vpc_endpoint" "ecr_api" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = local.ecr_api_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.subnet_ids
  security_group_ids = local.endpoint_sg_ids

  # CRITICAL: Private DNS must be enabled
  # Allows: ecr.{region}.amazonaws.com → private endpoint IP
  # Without this: API calls fail (resolve to public IP unreachable from private subnet)
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${local.vpc_id}-ecr-api-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECR-API-VPC-Endpoint"
    Service     = "ECR"
  }
}

################################################################################
# ENDPOINT 2: ECR DKR (Docker Registry Protocol)
#
# Purpose: Docker Registry v2 protocol for image pull/push
# - Docker pull: GET /v2/{repository}/manifests/{tag}
# - Docker pull: GET /v2/{repository}/blobs/{digest}
# - Docker push: PUT/POST /v2/{repository}/blobs/uploads/
# - Docker login: GET /v2/ (auth challenge)
#
# Accessed via: {account}.dkr.ecr.{region}.amazonaws.com
#
# Type: Interface
# Private DNS: REQUIRED ({account}.dkr.ecr.{region}.amazonaws.com → private IP)
################################################################################

resource "aws_vpc_endpoint" "ecr_dkr" {
  count = var.enable_ecr_endpoints ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = local.ecr_dkr_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.subnet_ids
  security_group_ids = local.endpoint_sg_ids

  # CRITICAL: Private DNS must be enabled
  # Allows: {account}.dkr.ecr.{region}.amazonaws.com → private endpoint IP
  # Without this: docker pull fails (cannot authenticate or fetch manifest)
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${local.vpc_id}-ecr-dkr-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "ECR-DKR-VPC-Endpoint"
    Service     = "ECR"
  }
}

################################################################################
# ENDPOINT 3: S3 Interface Endpoint (for ECR Layer Downloads)
#
# Purpose: ECR stores Docker image layers (blobs) in Amazon S3.
# When a container pulls an image:
#   1. ecr.api returns the manifest (list of layer digests)
#   2. ecr.dkr redirects layer downloads to S3 presigned URLs
#   3. The container runtime fetches each layer from S3
#
# Without S3 endpoint: layer downloads fail in private subnets because
#   the S3 presigned URLs point to public S3 endpoints.
#
# Why S3 Interface (not Gateway):
# - S3 Gateway endpoints do NOT provide private DNS
# - In private subnets, S3 hostnames resolve to public IPs
# - Without NAT, the connection hangs silently
# - S3 Interface endpoint provides private DNS → everything works
#
# Type: Interface (NOT Gateway - see explanation above)
# Private DNS: REQUIRED for ECR layer downloads to work
#
# Note: If you already have an S3 Interface Endpoint in this VPC,
#       set var.create_s3_endpoint = false to avoid duplicate endpoint error.
################################################################################

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_ecr_endpoints && var.create_s3_endpoint ? 1 : 0

  vpc_id            = local.vpc_id
  service_name      = local.s3_service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = local.subnet_ids
  security_group_ids = local.endpoint_sg_ids

  # CRITICAL: Private DNS must be enabled for ECR layer downloads
  # Without this: presigned S3 URLs resolve to public IPs → layer downloads fail
  private_dns_enabled = true

  tags = {
    Name        = "${var.env}-${var.project_id}-${local.vpc_id}-s3-interface-endpoint"
    Environment = var.env
    Project     = var.project_id
    ManagedBy   = "Terraform"
    Purpose     = "S3-Interface-for-ECR-Layers"
    Service     = "S3"
  }
}

