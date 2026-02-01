################################################################################
# Example: Basic Qdrant Deployment
#
# This example shows the minimal configuration needed to deploy Qdrant
# on EC2 ARM with automated backups and CloudWatch monitoring.
################################################################################

module "qdrant" {
  source = "../../ec2_qdrant_arm"

  # Environment
  env        = "production"
  project_id = "myapp"
  base_name  = "vector-db"

  # Network (update with your values)
  subnet_id = "subnet-xxxxx"
  security_group_ids = [
    "sg-xxxxx" # Must allow ports 6333 (REST) and 6334 (gRPC)
  ]

  # Instance
  instance_type = "t4g.large" # 2 vCPU, 8GB RAM, ~$49/month
  storage_size  = 50          # GB for vector data

  # API Key (leave empty to auto-generate)
  qdrant_api_key = "" # Auto-generated 32-char key

  # Backups (every 6 hours)
  enable_automated_backups = true
  backup_schedule          = "0 */6 * * *"
  backup_retention_days    = 7

  # Monitoring
  enable_cloudwatch_monitoring = true
  cloudwatch_retention_days    = 90

  # Security
  enable_ebs_encryption = true
  enable_ssh_key_access = false # Use Session Manager only

  tags = {
    Team        = "AI/ML"
    CostCenter  = "Engineering"
    Application = "Vector Search"
  }
}

################################################################################
# Outputs
################################################################################

output "qdrant_instance_id" {
  value = module.qdrant.qdrant.instance.id
}

output "qdrant_private_ip" {
  value = module.qdrant.qdrant.instance.private_ip
}

output "qdrant_rest_api_url" {
  value = module.qdrant.qdrant.connection.rest_api_url
}

output "session_manager_command" {
  value = module.qdrant.connect_via_session_manager
}

# Sensitive output (requires: terraform output -json qdrant_api_keys)
output "api_keys" {
  value     = module.qdrant.qdrant_api_keys
  sensitive = true
}

