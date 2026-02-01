################################################################################
# User Data Script - Native Qdrant Installation (No Docker)
#
# Purpose: Install Qdrant vector database natively on Ubuntu 24.04 ARM64
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
exec > >(tee /var/log/qdrant-setup.log)
exec 2>&1

echo "=== Starting Native Qdrant EC2 setup at $(date) ==="
echo "Architecture: $(uname -m)"

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

# Install AWS CLI v2 (for backups and Secrets Manager) - ARM64
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
            "file_path": "/var/log/qdrant-setup.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.qdrant_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/setup.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/qdrant/qdrant.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.qdrant_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/qdrant",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.qdrant_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.qdrant_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/cloud-init-output",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/qdrant-backup.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.qdrant_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/backup.log",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Qdrant/EC2",
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

# Retrieve API key from Secrets Manager
echo "Retrieving Qdrant API key from Secrets Manager..."
QDRANT_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id ${aws_secretsmanager_secret.qdrant_api_key.name} \
  --region ${data.aws_region.current.name} \
  --query SecretString \
  --output text)

# Install Qdrant natively (latest stable release for ARM64)
echo "Installing Qdrant..."
# Check for latest version at: https://github.com/qdrant/qdrant/releases
# ARM64 asset: qdrant-aarch64-unknown-linux-musl.tar.gz
QDRANT_VERSION="v1.12.5"  # Verified stable release (update as needed)
wget https://github.com/qdrant/qdrant/releases/download/$QDRANT_VERSION/qdrant-aarch64-unknown-linux-musl.tar.gz
tar -xzf qdrant-aarch64-unknown-linux-musl.tar.gz
mv qdrant /usr/local/bin/
chmod +x /usr/local/bin/qdrant
rm qdrant-aarch64-unknown-linux-musl.tar.gz

# Create qdrant user and directories
useradd -r -s /bin/false qdrant || true
mkdir -p /var/lib/qdrant/storage
mkdir -p /var/lib/qdrant/snapshots
mkdir -p /etc/qdrant
mkdir -p /var/log/qdrant
chown -R qdrant:qdrant /var/lib/qdrant /var/log/qdrant

# Create Qdrant configuration
# Note: Qdrant API key is set via environment variable, not config file
cat > /etc/qdrant/config.yaml <<'QDRANTCONFIG'
service:
  http_port: ${var.qdrant_http_port}
  grpc_port: ${var.qdrant_grpc_port}

storage:
  storage_path: /var/lib/qdrant/storage
  snapshots_path: /var/lib/qdrant/snapshots
  on_disk_payload: true

log_level: ${var.qdrant_log_level}

# Performance settings for ARM Graviton
cluster:
  enabled: false
QDRANTCONFIG

chown qdrant:qdrant /etc/qdrant/config.yaml
chmod 600 /etc/qdrant/config.yaml

# Create systemd service with API key as environment variable
cat > /etc/systemd/system/qdrant.service <<SYSTEMDSERVICE
[Unit]
Description=Qdrant Vector Database
After=network.target

[Service]
Type=simple
User=qdrant
Group=qdrant
Environment="QDRANT__SERVICE__API_KEY=$QDRANT_API_KEY"
ExecStart=/usr/local/bin/qdrant --config-path /etc/qdrant/config.yaml
Restart=always
RestartSec=10
StandardOutput=append:/var/log/qdrant/qdrant.log
StandardError=append:/var/log/qdrant/qdrant.log

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/qdrant /var/log/qdrant

[Install]
WantedBy=multi-user.target
SYSTEMDSERVICE

# Start and enable Qdrant
systemctl daemon-reload
systemctl enable qdrant
systemctl start qdrant

echo "Waiting for Qdrant to start..."
sleep 10

# Verify Qdrant is running
if systemctl is-active --quiet qdrant; then
  echo "Qdrant started successfully"
  curl -s http://localhost:${var.qdrant_http_port}/
else
  echo "ERROR: Qdrant failed to start"
  systemctl status qdrant --no-pager
fi

# Create Qdrant backup script (conditional based on variable)
if [ "${var.enable_automated_backups}" = "true" ] && [ "${local.backup_bucket_name}" != "" ]; then
  cat > /usr/local/bin/backup_qdrant.sh <<'BACKUPSCRIPT'
#!/bin/bash
set -e
TODAY=$(date +"%Y-%m-%d")
TIME=$(date +"%H%M%S")
SNAPSHOT_NAME="$TIME-full-snapshot"
BACKUP_DIR="/tmp/qdrant-backup-$TIME"

# Get API key from Secrets Manager
QDRANT_API_KEY=$(aws secretsmanager get-secret-value \
  --secret-id ${aws_secretsmanager_secret.qdrant_api_key.name} \
  --region ${data.aws_region.current.name} \
  --query SecretString \
  --output text)

# Create snapshot via Qdrant API
echo "Creating Qdrant snapshot..."
curl -X POST "http://localhost:${var.qdrant_http_port}/snapshots" \
  -H "api-key: $QDRANT_API_KEY" \
  -H "Content-Type: application/json"

# Wait for snapshot to complete
sleep 5

# Find latest snapshot
LATEST_SNAPSHOT=$(ls -t /var/lib/qdrant/snapshots/*.snapshot 2>/dev/null | head -1)

if [ -z "$LATEST_SNAPSHOT" ]; then
  echo "ERROR: No snapshot found"
  exit 1
fi

# Compress and upload to S3
mkdir -p $BACKUP_DIR
cp $LATEST_SNAPSHOT $BACKUP_DIR/
tar -czf /tmp/$TIME-qdrant-snapshot.tar.gz -C $BACKUP_DIR .
aws s3 cp /tmp/$TIME-qdrant-snapshot.tar.gz s3://${local.backup_bucket_name}/$TODAY/

# Cleanup
rm -rf $BACKUP_DIR /tmp/$TIME-qdrant-snapshot.tar.gz

echo "Backup completed at $(date)"
BACKUPSCRIPT

  chmod +x /usr/local/bin/backup_qdrant.sh
  echo "${var.backup_schedule} /usr/local/bin/backup_qdrant.sh >> /var/log/qdrant-backup.log 2>&1" | crontab -
fi

echo "=== Qdrant installation completed at $(date) ==="
echo "Qdrant Status:"
systemctl status qdrant --no-pager || true

echo "Qdrant Version:"
/usr/local/bin/qdrant --version || true

# Run initial backup if enabled
if [ "${var.enable_automated_backups}" = "true" ] && [ "${local.backup_bucket_name}" != "" ]; then
  echo "Running initial backup..."
  /usr/local/bin/backup_qdrant.sh || true
fi

# Disable and remove SSH (Session Manager only)
systemctl stop ssh || true
systemctl disable ssh || true
apt-get remove -y openssh-server || true

echo "=== Setup Complete ==="
EOF
}

################################################################################
# Attach User Data to Instance
################################################################################

# The user_data is used in main.tf via: user_data = local.user_data

