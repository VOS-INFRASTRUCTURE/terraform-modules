################################################################################
# EC2 Redis Module
#
# Purpose: Deploy self-managed Redis server on EC2 instance
#
# What This Module Does:
# - Launches ARM-based EC2 instance (t4g.micro default)
# - Installs and configures Redis server
# - Sets up security groups
# - Configures CloudWatch monitoring
# - Optional: Automated backups to S3
# - Optional: Systems Manager for SSH-less access
#
# Cost: ~$7-8/month for t4g.micro
#
# Use Cases:
# - Development/staging environments
# - Budget-constrained projects
# - Learning Redis
# - Non-critical caching
#
# ⚠️ Limitations:
# - No automatic failover (single instance)
# - Manual maintenance required
# - You manage OS updates, Redis updates, backups
#
# For production with HA, consider ElastiCache instead.
################################################################################

################################################################################
# Data Sources
################################################################################

data "aws_ami" "ubuntu_arm64" {
  count       = var.enable_ec2_redis && var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["099720109477"] # Canonical (Ubuntu)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


################################################################################
# Locals Configs
################################################################################

locals {
  # Calculate max memory based on instance type (75% of RAM)
  instance_memory_map = {
    "t4g.nano"   = "256mb"
    "t4g.micro"  = "768mb"
    "t4g.small"  = "1536mb"
    "t4g.medium" = "3072mb"
  }

  redis_max_memory = var.redis_max_memory == "auto" ? lookup(local.instance_memory_map, var.instance_type, "768mb") : var.redis_max_memory
}


################################################################################
# EC2 Instance
################################################################################

resource "aws_instance" "redis" {
  count = var.enable_ec2_redis ? 1 : 0

  ami                    = var.ami_id != "" ? var.ami_id : data.aws_ami.ubuntu_arm64[0].id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.redis[0].id]
  iam_instance_profile   = aws_iam_instance_profile.redis[0].name
  key_name               = var.key_pair_name != "" ? var.key_pair_name : null

  monitoring = var.enable_cloudwatch_monitoring

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = var.enable_ebs_encryption
    delete_on_termination = true

    tags = merge(
      {
        Name        = "${var.env}-${var.project_id}-redis-root"
        Environment = var.env
        Project     = var.project_id
        ManagedBy   = "Terraform"
      },
      var.tags
    )
  }

  user_data = base64encode(local.user_data)

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Redis-Server"
      CostCenter  = "Infrastructure"
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

