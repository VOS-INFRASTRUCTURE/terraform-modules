################################################################################
# Example: Production Qdrant with High Availability Features
#
# This example includes:
# - Larger instance for production workload
# - EBS snapshots with cross-region DR
# - Extended backup retention
# - Detailed monitoring
################################################################################

module "qdrant_production" {
  source = "../../ec2_qdrant_arm"

  # Environment
  env        = "production"
  project_id = "enterprise-app"
  base_name  = "qdrant"

  # Network
  subnet_id          = "subnet-xxxxx"
  security_group_ids = ["sg-xxxxx"]

  # Instance - Production-grade
  instance_type = "m7g.xlarge" # 4 vCPU, 16GB RAM, ~$134/month
  storage_size  = 200          # GB for large vector collections

  # API Keys - Custom (or leave empty for auto-generation)
  qdrant_api_key           = var.qdrant_api_key
  qdrant_read_only_api_key = var.qdrant_read_only_api_key

  # Backups - Frequent with longer retention
  enable_automated_backups = true
  backup_schedule          = "0 */4 * * *" # Every 4 hours
  backup_retention_days    = 30            # 30-day retention

  # EBS Snapshots for disaster recovery
  enable_ebs_snapshots         = true
  ebs_snapshot_interval_hours  = 24
  ebs_snapshot_retention_count = 14 # 14 daily snapshots

  # Cross-region DR
  enable_cross_region_snapshot_copy = true
  snapshot_dr_region                = "us-west-2"
  snapshot_dr_retention_days        = 30

  # Monitoring
  enable_cloudwatch_monitoring = true
  cloudwatch_retention_days    = 365 # 1-year retention
  enable_detailed_monitoring   = true # 1-min EC2 metrics

  # Security
  enable_ebs_encryption       = true
  enable_ssh_key_access       = false
  enable_termination_protection = true # Prevent accidental termination

  tags = {
    Environment = "Production"
    Team        = "AI/ML"
    CostCenter  = "Engineering"
    Compliance  = "Required"
    Backup      = "Critical"
  }
}

################################################################################
# Variables (define in terraform.tfvars or environment)
################################################################################

variable "qdrant_api_key" {
  description = "Qdrant API key (use strong 32+ char key)"
  type        = string
  sensitive   = true
}

variable "qdrant_read_only_api_key" {
  description = "Qdrant read-only API key"
  type        = string
  sensitive   = true
}

################################################################################
# Outputs
################################################################################

output "qdrant_instance" {
  value = {
    id         = module.qdrant_production.qdrant.instance.id
    private_ip = module.qdrant_production.qdrant.instance.private_ip
    type       = module.qdrant_production.qdrant.instance.instance_type
  }
}

output "qdrant_endpoints" {
  value = {
    rest_api = module.qdrant_production.qdrant.connection.rest_api_url
    grpc     = module.qdrant_production.qdrant.connection.grpc_url
  }
}

output "backup_info" {
  value = module.qdrant_production.qdrant.backups
}

output "monitoring" {
  value = module.qdrant_production.qdrant.monitoring
}

