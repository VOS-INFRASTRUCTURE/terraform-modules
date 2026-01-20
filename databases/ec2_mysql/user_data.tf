
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
    # Security
    skip-name-resolve
    local-infile=0

    # Performance
    max_connections=${var.mysql_max_connections}
    innodb_buffer_pool_size=${var.innodb_buffer_pool_size}

    # Logging
    log_error=/var/lib/mysql/error.log
    slow_query_log=1
    slow_query_log_file=/var/lib/mysql/slow-query.log
    long_query_time=2

    # Character set
    character-set-server=utf8mb4
    collation-server=utf8mb4_unicode_ci

    # Binary logging for backups
    log-bin=/var/lib/mysql/mysql-bin
    binlog_expire_logs_seconds=604800
    max_binlog_size=100M
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
