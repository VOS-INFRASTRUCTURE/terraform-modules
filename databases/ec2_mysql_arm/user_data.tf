################################################################################
# User Data Script - Native MySQL Installation (No Docker)
#
# Purpose: Install MySQL 8.x natively on Ubuntu 24.04 ARM64
# Benefits over Docker:
#   - 5-10% better performance (no Docker overhead)
#   - 200-500MB less memory usage (no Docker daemon)
#   - Simpler architecture (one less layer)
#   - Direct access to logs and configuration
#   - Full ARM optimization
################################################################################

locals {
  user_data = <<-EOF
#!/bin/bash
set -e

# Log everything to a file
exec > >(tee /var/log/mysql-setup.log)
exec 2>&1

echo "=== Starting Native MySQL EC2 setup at $(date) ==="
echo "Architecture: $(uname -m)"
echo "Instance type: ARM64 (Graviton)"

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

# Install AWS CLI v2 (for backups and Secrets Manager)
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "/tmp/awscliv2.zip"
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install
rm -rf /tmp/awscliv2.zip /tmp/aws

# Install CloudWatch agent (conditional based on variable)
if [ "${var.enable_cloudwatch_monitoring}" = "true" ]; then
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
  dpkg -i amazon-cloudwatch-agent.deb

  # Configure CloudWatch agent
  cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json <<'CWCONFIG'
{
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
            "file_path": "/var/lib/mysql/error.log",
            "log_group_name": "${aws_cloudwatch_log_group.mysql_logs[0].name}",
            "log_stream_name": "{instance_id}/mysql-error",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/lib/mysql/slow-query.log",
            "log_group_name": "${aws_cloudwatch_log_group.mysql_logs[0].name}",
            "log_stream_name": "{instance_id}/mysql-slow-query",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${aws_cloudwatch_log_group.mysql_logs[0].name}",
            "log_stream_name": "{instance_id}/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/mysql-backup.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.mysql_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/backup.log",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "MySQL/EC2",
    "metrics_collected": {
      "cpu": {
        "measurement": [{"name": "cpu_usage_idle", "rename": "CPU_IDLE", "unit": "Percent"}],
        "totalcpu": false
      },
      "disk": {
        "measurement": [{"name": "used_percent", "rename": "DISK_USED", "unit": "Percent"}],
        "resources": ["*"]
      },
      "mem": {
        "measurement": [{"name": "mem_used_percent", "rename": "MEM_USED", "unit": "Percent"}]
      }
    }
  }
}
CWCONFIG

  # Start CloudWatch agent
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

# Install MySQL Server 8.0 natively
echo "Installing MySQL Server 8.0..."
apt-get install -y mysql-server

# Stop MySQL to configure it
systemctl stop mysql

# Create MySQL configuration directory
mkdir -p /etc/mysql/mysql.conf.d

# Create custom MySQL configuration from template
cat > /etc/mysql/mysql.conf.d/z-custom.cnf <<'MYSQLCONF'
${templatefile("${path.module}/mysql.min.cnf", {
  innodb_buffer_pool_size = var.innodb_buffer_pool_size
  mysql_max_connections   = var.mysql_max_connections
})}
MYSQLCONF

# Create MySQL log directory
mkdir -p /var/log/mysql
chown mysql:mysql /var/log/mysql

# Create MySQL data directory (if not exists)
mkdir -p /var/lib/mysql
chown mysql:mysql /var/lib/mysql

# Start MySQL
systemctl start mysql
systemctl enable mysql

echo "Waiting for MySQL to start..."
sleep 10

# Set root password
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';"

# Create application database
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE IF NOT EXISTS ${var.mysql_database};"

# Create application user
MYSQL_USER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id ${aws_secretsmanager_secret.mysql_user_password.name} \
  --region ${data.aws_region.current.name} \
  --query SecretString \
  --output text)

mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<MYSQL_SCRIPT
CREATE USER IF NOT EXISTS '${var.mysql_user}'@'%' IDENTIFIED BY '$MYSQL_USER_PASSWORD';
GRANT ALL PRIVILEGES ON ${var.mysql_database}.* TO '${var.mysql_user}'@'%';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Create MySQL restart script for reboot
cat > /usr/local/bin/restart_mysql.sh <<'RESTART_SCRIPT'
#!/bin/bash
systemctl restart mysql
RESTART_SCRIPT

chmod +x /usr/local/bin/restart_mysql.sh

# Create MySQL backup script (conditional based on variable)
if [ "${var.enable_automated_backups}" = "true" ] && [ "${local.backup_bucket_name}" != "" ]; then
  cat > /usr/local/bin/backup_mysql.sh <<'BACKUPSCRIPT'
#!/bin/bash
set -e
TODAY=$(date +"%Y-%m-%d")
TIME=$(date +"%H%M%S")
BACKUP_FILE="/tmp/$TIME-all-databases.sql.gz"
MYSQL_ROOT_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id ${aws_secretsmanager_secret.mysql_root_password.name} \
  --region ${data.aws_region.current.name} \
  --query SecretString \
  --output text)

mysqldump \
  -u root \
  -p"$MYSQL_ROOT_PASSWORD" \
  --all-databases \
  --single-transaction \
  --quick \
  --lock-tables=false \
  --routines \
  --triggers \
  --events \
  | gzip > $BACKUP_FILE

aws s3 cp $BACKUP_FILE s3://${local.backup_bucket_name}/mysql-backups/${var.env}/${var.project_id}/$TODAY/$TIME-all-databases.sql.gz
rm -f $BACKUP_FILE
echo "Backup completed at $(date)"
BACKUPSCRIPT

  chmod +x /usr/local/bin/backup_mysql.sh
  echo "${var.backup_schedule} /usr/local/bin/backup_mysql.sh >> /var/log/mysql-backup.log 2>&1" | crontab -
fi

# Add MySQL startup to crontab for reboot
(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/restart_mysql.sh") | crontab -

echo "=== MySQL installation completed at $(date) ==="
echo "MySQL Status:"
systemctl status mysql --no-pager
echo "MySQL Version:"
mysql --version

# Run initial backup if enabled
if [ "${var.enable_automated_backups}" = "true" ] && [ "${local.backup_bucket_name}" != "" ]; then
  echo "Running initial backup..."
  /usr/local/bin/backup_mysql.sh
fi


# Disable and remove SSH (Session Manager only)
systemctl stop ssh || true
systemctl disable ssh || true
apt-get remove -y openssh-server

echo "=== Setup Complete ==="
EOF
}

################################################################################
# Attach User Data to Instance
################################################################################

# The user_data is used in main.tf via: user_data = local.user_data

