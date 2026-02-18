
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
exec > >(tee /var/log/server-setup.log)
exec 2>&1

echo "=== Starting  EC2 setup at $(date) ==="

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
    "namespace": "EC2/",
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
            "file_path": "/var/log/server-setup.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/setup.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/syslog",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/auth.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/cloud-init.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
            "log_stream_name": "{instance_id}/cloud-init-output.log",
            "timezone": "UTC"
          },
          {
            "file_path": "/var/log/docker.log",
            "log_group_name": "${var.enable_cloudwatch_monitoring ? aws_cloudwatch_log_group.ec2_x86_logs[0].name : ""}",
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

# Disable and remove SSH (Session Manager only)
systemctl stop ssh || true
systemctl disable ssh || true
apt-get remove -y openssh-server


echo "===  EC2 setup completed at $(date) ==="
EOF
}
