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
# Security Group for Redis
################################################################################

resource "aws_security_group" "redis" {
  count = var.enable_ec2_redis ? 1 : 0

  name        = "${var.env}-${var.project_id}-redis-sg"
  description = "Security group for Redis EC2 instance"
  vpc_id      = var.vpc_id

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-sg"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Redis-SecurityGroup"
    },
    var.tags
  )
}

# Allow Redis access from application security groups
resource "aws_security_group_rule" "redis_from_app_sg" {
  count = var.enable_ec2_redis && length(var.allowed_security_group_ids) > 0 ? length(var.allowed_security_group_ids) : 0

  type                     = "ingress"
  from_port                = var.redis_port
  to_port                  = var.redis_port
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_group_ids[count.index]
  security_group_id        = aws_security_group.redis[0].id
  description              = "Redis access from application security group"
}

# Allow Redis access from CIDR blocks
resource "aws_security_group_rule" "redis_from_cidr" {
  count = var.enable_ec2_redis && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = var.redis_port
  to_port           = var.redis_port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.redis[0].id
  description       = "Redis access from allowed CIDR blocks"
}

# Allow all outbound traffic (for updates, CloudWatch, etc.)
resource "aws_security_group_rule" "redis_outbound" {
  count = var.enable_ec2_redis ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.redis[0].id
  description       = "Allow all outbound traffic"
}

################################################################################
# CloudWatch Log Group
################################################################################

resource "aws_cloudwatch_log_group" "redis" {
  count = var.enable_ec2_redis && var.enable_cloudwatch_logs ? 1 : 0

  name              = "/aws/ec2/${var.env}-${var.project_id}-redis"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-redis-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "Redis-Logs"
    },
    var.tags
  )
}

################################################################################
# User Data Script for Redis Installation
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

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Log everything to a file
    exec > >(tee /var/log/redis-setup.log)
    exec 2>&1

    echo "=== Starting Redis installation at $(date) ==="

    # Update system
    apt-get update
    apt-get upgrade -y

    # Install Redis
    apt-get install -y redis-server

    # Stop Redis to configure it
    systemctl stop redis-server

    # Backup original config
    cp /etc/redis/redis.conf /etc/redis/redis.conf.backup

    # Configure Redis
    cat > /etc/redis/redis.conf <<'REDISCONF'
    # Redis Configuration - Managed by Terraform

    # Network
    bind 0.0.0.0
    port ${var.redis_port}
    protected-mode yes
    tcp-backlog 511
    timeout 0
    tcp-keepalive 300

    # General
    daemonize yes
    supervised systemd
    pidfile /var/run/redis/redis-server.pid
    loglevel notice
    logfile /var/log/redis/redis-server.log

    # Memory Management
    maxmemory ${local.redis_max_memory}
    maxmemory-policy ${var.redis_max_memory_policy}

    # Persistence (RDB)
    ${var.enable_redis_persistence ? "save 900 1" : "# RDB disabled"}
    ${var.enable_redis_persistence ? "save 300 10" : ""}
    ${var.enable_redis_persistence ? "save 60 10000" : ""}
    dbfilename dump.rdb
    dir /var/lib/redis

    # Persistence (AOF)
    appendonly ${var.enable_redis_aof ? "yes" : "no"}
    appendfilename "appendonly.aof"
    appendfsync everysec

    # Security
    ${var.redis_password != "" ? "requirepass ${var.redis_password}" : "# No password set"}

    # Performance
    slowlog-log-slower-than 10000
    slowlog-max-len 128
    REDISCONF

    # Set proper permissions
    chown redis:redis /etc/redis/redis.conf
    chmod 640 /etc/redis/redis.conf

    # Enable and start Redis
    systemctl enable redis-server
    systemctl start redis-server

    # Wait for Redis to start
    sleep 5

    # Verify Redis is running
    if systemctl is-active --quiet redis-server; then
        echo "=== Redis successfully started ==="
        redis-cli ping || echo "Warning: Redis not responding to PING"
    else
        echo "ERROR: Redis failed to start"
        systemctl status redis-server
        exit 1
    fi

    # Install and configure CloudWatch agent if monitoring enabled
    %{if var.enable_cloudwatch_monitoring || var.enable_cloudwatch_logs}
    apt-get install -y amazon-cloudwatch-agent

    cat > /opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json <<'CWCONFIG'
    {
      "metrics": {
        "namespace": "EC2/Redis",
        "metrics_collected": {
          "mem": {
            "measurement": [
              {"name": "mem_used_percent", "rename": "MemoryUsed", "unit": "Percent"}
            ],
            "metrics_collection_interval": 60
          },
          "disk": {
            "measurement": [
              {"name": "used_percent", "rename": "DiskUsed", "unit": "Percent"}
            ],
            "metrics_collection_interval": 60,
            "resources": ["*"]
          }
        }
      },
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/redis/redis-server.log",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/redis.log"
              }
            ]
          }
        }
      }
    }
    CWCONFIG

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config \
      -m ec2 \
      -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/cloudwatch-config.json
    %{endif}

    # Setup automated backups if enabled
    %{if var.enable_automated_backups && var.backup_s3_bucket_name != ""}
    cat > /usr/local/bin/redis-backup.sh <<'BACKUPSCRIPT'
    #!/bin/bash
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    BACKUP_FILE="/tmp/redis-backup-$TIMESTAMP.rdb"

    # Trigger Redis save
    redis-cli %{if var.redis_password != ""}-a ${var.redis_password}%{endif} BGSAVE

    # Wait for save to complete
    sleep 10

    # Copy RDB file
    cp /var/lib/redis/dump.rdb $BACKUP_FILE

    # Upload to S3
    aws s3 cp $BACKUP_FILE s3://${var.backup_s3_bucket_name}/redis-backups/${var.env}/${var.project_id}/

    # Cleanup
    rm $BACKUP_FILE

    echo "Backup completed: $TIMESTAMP"
    BACKUPSCRIPT

    chmod +x /usr/local/bin/redis-backup.sh

    # Add cron job
    echo "${var.backup_schedule} /usr/local/bin/redis-backup.sh >> /var/log/redis-backup.log 2>&1" | crontab -
    %{endif}

    echo "=== Redis setup completed at $(date) ==="
  EOF
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

