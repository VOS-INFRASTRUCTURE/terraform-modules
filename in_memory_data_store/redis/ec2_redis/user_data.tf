
################################################################################
# User Data Script for Redis Installation
################################################################################

locals {
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
