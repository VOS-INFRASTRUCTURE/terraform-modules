
################################################################################
# User Data Script
################################################################################
# Note that session manager agent is pre-installed on Ubuntu 24.04, so no need
# to install it separately.

locals {
  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Log everything to a file
    exec > >(tee /var/log/mysql-setup.log)
    exec 2>&1

    echo "=== Starting MySQL EC2 setup at $(date) ==="

    # Update system
    apt-get update -y
    apt-get upgrade -y

    # Install required packages
    apt-get install -y \
      apt-transport-https \
      ca-certificates \
      curl \
      software-properties-common \
      gnupg-agent \
      jq \
      unzip

    # Install AWS CLI v2 (awscli package not available in Ubuntu 24.04)
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws

    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh

    # Start and enable Docker
    systemctl start docker
    systemctl enable docker

    # Add ubuntu user to docker group
    usermod -aG docker ubuntu

    # Install CloudWatch agent (conditional based on variable)
    if [ "${var.enable_cloudwatch_monitoring}" = "true" ]; then
      wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
      dpkg -i amazon-cloudwatch-agent.deb

      # Configure CloudWatch agent
      cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWCONFIG'
    {
      "metrics": {
        "namespace": "EC2/MySQL",
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
                "file_path": "/var/log/mysql-setup.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/setup.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/home/ubuntu/mysql_data/error.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/mysql-error.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/home/ubuntu/mysql_data/slow-query.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/mysql-slow.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/mysql-backup.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/backup.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/syslog",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/syslog",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/auth.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/auth.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/cloud-init.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/cloud-init.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/cloud-init-output.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/cloud-init-output.log",
                "timezone": "UTC"
              },
              {
                "file_path": "/var/log/docker.log",
                "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
                "log_stream_name": "{instance_id}/docker.log",
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
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
    fi

    # Retrieve secrets from Secrets Manager
    echo "Retrieving MySQL passwords from Secrets Manager..."
    MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} \
      --region ${data.aws_region.current.name} \
      --query SecretString \
      --output text)

    MYSQL_USER_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.mysql_user_password.name} \
      --region ${data.aws_region.current.name} \
      --query SecretString \
      --output text)

    # Create MySQL data directory
    mkdir -p /home/ubuntu/mysql_data
    chown -R ubuntu:ubuntu /home/ubuntu/mysql_data

    # Create MySQL custom configuration
    mkdir -p /home/ubuntu/mysql_config
    cat > /home/ubuntu/mysql_config/my.cnf <<'MYSQLCONF'
    [mysqld]

    ################################################################################
    # BASICS & SECURITY
    ################################################################################

    # Run MySQL as this system user. user mysql is default if not specified.
    # Test: ps -ef | grep mysqld
    user=mysql

    # Skip DNS lookups for connecting hosts (improves connection speed)
    # Security: Prevents DNS-based attacks
    # Performance: Faster connections (no DNS resolution delay)
    # Use IP addresses in GRANT statements when this is enabled
    skip-name-resolve

    # Disable LOAD DATA LOCAL INFILE (security hardening)
    # Prevents local file system access via SQL injection
    # Keep disabled unless you specifically need this feature
    local-infile=0

    # MySQL 8 SQL Mode – Strict Error Handling & Data Integrity
    # ONLY_FULL_GROUP_BY: Prevents ambiguous queries using GROUP BY
    # STRICT_TRANS_TABLES: Rejects invalid or truncated data
    # NO_ZERO_IN_DATE: Prevents invalid dates like '2026-00-15'
    # NO_ZERO_DATE: Prevents completely zero dates like '0000-00-00'
    # ERROR_FOR_DIVISION_BY_ZERO: Raises error on division by zero
    # NO_ENGINE_SUBSTITUTION: Prevents silent substitution of storage engines
    sql_mode=ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION

    ################################################################################
    # CONNECTION HANDLING
    ################################################################################

    # Maximum simultaneous client connections
    # Rule: Set based on your app's connection pool size
    # Too high: Wastes memory (each connection uses ~256KB-1MB)
    # Too low: Connection errors during traffic spikes
    # For most apps: 100-300 is sufficient (use connection pooling!)
    max_connections=${var.mysql_max_connections}

    # Prevent Host Blocking After Failed Connection Attempts
    # Default is 100 (very low), which can cause accidental lockouts
    # Setting this high reduces risk of accidental blocks during deployments
    max_connect_errors=100000

    # Seconds before closing inactive non-interactive connections
    # Interactive = mysql CLI, Non-interactive = app connections
    # 600s (10 min) is reasonable for most apps with connection pooling
    wait_timeout=600
    interactive_timeout=600

    # Thread Cache Size – Reduce Thread Creation Overhead
    # Number of threads MySQL keeps in cache for reuse
    # Recommended: 10-50% of max_connections
    thread_cache_size=100

    ################################################################################
    # InnoDB CORE SETTINGS (⚠️ MOST IMPORTANT FOR PERFORMANCE)
    ################################################################################

    # Use InnoDB as default storage engine (ACID-compliant, transactional)
    # InnoDB is the only production-grade engine in MySQL 8
    default_storage_engine=InnoDB

    # InnoDB buffer pool size (THE MOST CRITICAL SETTING)
    # Purpose: Caches table data and indexes in memory
    # Rules: Dedicated DB server: 70-75% of RAM, Shared: 50-60% of RAM
    # Examples: 4GB RAM → 3G, 8GB RAM → 6G, 16GB RAM → 12G
    innodb_buffer_pool_size=${var.innodb_buffer_pool_size}

    # InnoDB Buffer Pool Instances – Improve Concurrency
    # Reduces internal locking contention
    # Rule: 1 instance per GB of buffer pool (up to 8-16)
    innodb_buffer_pool_instances=4

    # InnoDB Redo Log File Size – Transaction Logging
    # Larger = Better write performance, slower crash recovery
    # Recommended total redo log space: 1G-4G
    innodb_log_file_size=1G

    # InnoDB Log Buffer Size – Memory for Redo Log Writes
    # Larger buffer = Fewer disk writes, better for write-heavy workloads
    # Default 16M is often too small; 64M-256M recommended
    innodb_log_buffer_size=64M

    # Flush method – how MySQL writes data to disk
    # O_DIRECT: Bypasses OS cache to prevent double buffering
    # Recommended for dedicated DB servers
    innodb_flush_method=O_DIRECT

    # Durability vs. performance: log flushing on transaction commit
    # 1 = Flush log to disk on every commit (ACID-safe, safest)
    # 2 = Flush logs every second (~1 sec data loss risk, faster)
    # Keep at 1 for production
    innodb_flush_log_at_trx_commit=1

    # Store each InnoDB table in its own .ibd file
    # Benefits: easier backups, reclaim space on DROP TABLE, better I/O
    innodb_file_per_table=1

    # I/O capacity for background tasks (flushes, checkpoints)
    # Based on disk IOPS: HDD=200, gp2=3000, gp3=2000-4000, NVMe=10000+
    innodb_io_capacity=2000
    innodb_io_capacity_max=4000

    # Number of I/O threads for read and write operations
    # For SSD: 4-8 each, ARM/Graviton: 4 is sufficient
    innodb_read_io_threads=4
    innodb_write_io_threads=4

    ################################################################################
    # TEMPORARY TABLES & MEMORY
    ################################################################################

    # Maximum size for in-memory temporary tables
    # When exceeded, temp table is written to disk (slower)
    # Used for: GROUP BY, ORDER BY, DISTINCT, UNION
    tmp_table_size=64M
    max_heap_table_size=64M

    # Internal temporary table storage engine
    # TempTable: New in MySQL 8, faster than MEMORY engine
    internal_tmp_mem_storage_engine=TempTable

    ################################################################################
    # QUERY CACHE (MySQL 8.0: REMOVED/DISABLED)
    ################################################################################

    # Query cache was removed in MySQL 8.0
    # These settings have no effect but kept for backward compatibility
    query_cache_type=0
    query_cache_size=0

    ################################################################################
    # LOGGING (MONITORING & DEBUGGING)
    ################################################################################

    # Error log location (startup issues, crashes, warnings)
    log_error=/var/lib/mysql/error.log

    # Slow query log (identify performance bottlenecks)
    # Essential for production monitoring and optimization
    slow_query_log=1
    slow_query_log_file=/var/lib/mysql/slow-query.log

    # Queries taking longer than this are logged (in seconds)
    # 1 second is a good starting point
    long_query_time=1

    # Log queries that don't use indexes
    # 0 = Don't log (recommended for production - too noisy)
    # 1 = Log (useful for dev/staging to find missing indexes)
    log_queries_not_using_indexes=0

    ################################################################################
    # BINARY LOGGING (BACKUPS & POINT-IN-TIME RECOVERY)
    ################################################################################

    # Enable binary logging for backups and replication
    # Required for point-in-time recovery
    log-bin=/var/lib/mysql/mysql-bin

    # Binary log format
    # ROW: Logs actual row changes (safest, recommended)
    binlog_format=ROW

    # Binary log retention period (in seconds)
    # 172800 = 2 days (sufficient with hourly S3 backups + daily EBS snapshots)
    # Saves disk space compared to 7-day retention
    binlog_expire_logs_seconds=172800

    # Sync binary log to disk after every commit
    # 1 = Safest (no binlog data loss), recommended for production
    sync_binlog=1

    # Maximum size of a single binary log file before rotation
    # 100M rotates frequently, easier to manage
    max_binlog_size=100M

    ################################################################################
    # CHARACTER SET & COLLATION
    ################################################################################

    # Default character set for all databases and tables
    # utf8mb4: Full UTF-8 support (including emojis, 4-byte characters)
    # Always use utf8mb4 for new applications
    character-set-server=utf8mb4

    # Default collation (sorting/comparison rules)
    # utf8mb4_unicode_ci: Better sorting for international characters
    collation-server=utf8mb4_unicode_ci

    ################################################################################
    # NETWORKING
    ################################################################################

    # IP address to bind to
    # 0.0.0.0: Listen on all interfaces (allows remote connections)
    # For Docker/EC2: Use 0.0.0.0, control access via security groups
    bind-address=0.0.0.0

    # Disable internal host cache (related to skip-name-resolve)
    # Prevents issues with cached DNS lookups
    skip-host-cache
    MYSQLCONF

    chown -R ubuntu:ubuntu /home/ubuntu/mysql_config

    # Create MySQL startup script
    cat > /usr/local/bin/start_mysql_container.sh <<'STARTSCRIPT'
    #!/bin/bash

    # Stop existing container if running
    docker stop mysql-server 2>/dev/null || true
    docker rm mysql-server 2>/dev/null || true

    # Retrieve secrets from Secrets Manager
    MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} \
      --region ${data.aws_region.current.name} \
      --query SecretString \
      --output text)

    MYSQL_USER_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.mysql_user_password.name} \
      --region ${data.aws_region.current.name} \
      --query SecretString \
      --output text)

    # Start MySQL container
    docker run -d \
      --name mysql-server \
      -e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
      -e MYSQL_DATABASE="${var.mysql_database}" \
      -e MYSQL_USER="${var.mysql_user}" \
      -e MYSQL_PASSWORD="$MYSQL_USER_PASSWORD" \
      -v /home/ubuntu/mysql_data:/var/lib/mysql \
      -v /home/ubuntu/mysql_config/my.cnf:/etc/mysql/conf.d/custom.cnf:ro \
      -p 3306:3306 \
      --restart always \
      --health-cmd='mysqladmin ping -h localhost' \
      --health-interval=10s \
      --health-timeout=5s \
      --health-retries=3 \
      mysql:${var.mysql_version}

    echo "MySQL container started at $(date)"
    STARTSCRIPT

    chmod +x /usr/local/bin/start_mysql_container.sh

    # Create MySQL backup script (conditional based on variable)
    if [ "${var.enable_automated_backups}" = "true" ] && [ "${local.backup_bucket_name}" != "" ]; then
      cat > /usr/local/bin/backup_mysql.sh <<'BACKUPSCRIPT'
    #!/bin/bash
    set -e

    TODAY=$(date +"%Y-%m-%d")
    TIMESTAMP=$(date +"%H%M%S")
    FOLDER_NAME="$TODAY-${var.mysql_database}"
    BACKUP_FILE="/tmp/mysql-backup-$TIMESTAMP.sql.gz"
    S3_PATH="s3://${local.backup_bucket_name}/mysql-backups/${var.env}/${var.project_id}/$FOLDER_NAME/"

    echo "Starting MySQL backup at $(date)"

    # Get root password from Secrets Manager
    MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
      --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} \
      --region ${data.aws_region.current.name} \
      --query SecretString \
      --output text)

    # Backup all databases
    docker exec mysql-server mysqldump \
      -u root \
      -p"$MYSQL_ROOT_PASSWORD" \
      --all-databases \
      --single-transaction \
      --quick \
      --lock-tables=false \
      | gzip > $BACKUP_FILE

    # Upload to S3 with folder structure: YYYY-MM-DD-database-name/HHMMSS.sql.gz
    aws s3 cp $BACKUP_FILE $S3_PATH

    # Cleanup local backup
    rm $BACKUP_FILE

    # Note: S3 backup retention is managed by S3 lifecycle rules
    # EC2 instance does NOT have s3:DeleteObject permission for security
    # To enable automatic cleanup, configure S3 lifecycle policy:
    #   - Expire objects after ${var.backup_retention_days} days
    #   - Or use S3 Intelligent-Tiering for cost optimization

    echo "MySQL backup completed at $(date)"
    echo "Backup stored in: $S3_PATH"
    BACKUPSCRIPT

      chmod +x /usr/local/bin/backup_mysql.sh

      # Add backup to crontab (runs per schedule: ${var.backup_schedule})
      echo "${var.backup_schedule} /usr/local/bin/backup_mysql.sh >> /var/log/mysql-backup.log 2>&1" | crontab -
    fi

    # Add MySQL startup to crontab for reboot
    (crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/start_mysql_container.sh") | crontab -

    # Start MySQL container
    /usr/local/bin/start_mysql_container.sh

    # Wait for MySQL to be ready
    echo "Waiting for MySQL to be ready..."
    for i in {1..30}; do
      if docker exec mysql-server mysqladmin ping -h localhost --silent; then
        echo "MySQL is ready!"
        break
      fi
      echo "Waiting for MySQL... ($i/30)"
      sleep 2
    done


    # Disable and remove SSH (Session Manager only)
    systemctl stop ssh || true
    systemctl disable ssh || true
    apt-get remove -y openssh-server


    echo "=== MySQL EC2 setup completed at $(date) ==="
    EOF
}
