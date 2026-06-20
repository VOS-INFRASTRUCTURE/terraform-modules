
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

    # Add Redis.io official repository (provides versions newer than Ubuntu default)
    apt-get install -y curl gnupg lsb-release
    curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/redis.list
    apt-get update

    # Pin to the requested minor version (e.g. "7.4" matches 6:7.4.8-1rl1~noble1 at runtime)
    REDIS_MINOR="${var.redis_version}"
    PKG_VERSION=$(apt-cache show redis-server 2>/dev/null | grep "^Version:" | awk '{print $2}' | grep ":$REDIS_MINOR\." | head -1)
    if [ -z "$PKG_VERSION" ]; then
      echo "ERROR: Redis $REDIS_MINOR.x not found in Redis.io repository. Available:"
      apt-cache show redis-server 2>/dev/null | grep "^Version:"
      exit 1
    fi
    echo "=== Installing Redis $PKG_VERSION ==="
    apt-get install -y redis-server=$PKG_VERSION redis-tools=$PKG_VERSION

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
                "log_stream_name": "{instance_id}/redis.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/redis-setup.log",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/setup.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/syslog",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/syslog",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/auth.log",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/auth.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/cloud-init.log",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/cloud-init.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/cloud-init-output.log",
                "log_group_name": "%{if var.enable_cloudwatch_logs}${aws_cloudwatch_log_group.redis[0].name}%{endif}",
                "log_stream_name": "{instance_id}/cloud-init-output.log",
                "timezone": "UTC"
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

    echo "=== Redis setup completed at $(date) ==="
  EOF
}
