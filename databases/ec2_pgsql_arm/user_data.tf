################################################################################
# User Data Script - Native PostgreSQL 16 Installation (No Docker)
#
# Purpose: Install PostgreSQL 16 natively on Ubuntu 24.04 ARM64
# Strategy: Minimal bootstrap script to stay under 16KB limit
################################################################################

locals {
  # PostgreSQL configuration content (minified version without comments for size reduction)
  pgsql_config = templatefile("${path.module}/postgresql.min.conf", {
    shared_buffers       = var.shared_buffers
    effective_cache_size = var.effective_cache_size
    max_connections      = var.max_connections
  })

  # pg_hba.conf content
  pg_hba_config = file("${path.module}/pg_hba.conf")

  # Minimal user_data script - stays well under 16KB
  user_data = <<-EOF
#!/bin/bash
set -e
exec > >(tee /var/log/pgsql-setup.log) 2>&1

echo "=== PostgreSQL ARM Setup Started: $(date) ==="

# Install essentials
apt-get update -y && apt-get install -y curl unzip jq postgresql postgresql-contrib

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "/tmp/aws.zip"
unzip -q /tmp/aws.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws*

# Get PostgreSQL postgres password
POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_postgres_password.name} --region ${data.aws_region.current.name} --query SecretString --output text)

# Stop PostgreSQL
systemctl stop postgresql

# Configure PostgreSQL
if ! grep -q "### CUSTOM_PG_CONF ###" /etc/postgresql/16/main/postgresql.conf; then
  cat >> /etc/postgresql/16/main/postgresql.conf << 'PGSQLCONF'
### CUSTOM_PG_CONF ###
${local.pgsql_config}
### END CUSTOM_PG_CONF ###
PGSQLCONF
fi

cat > /etc/postgresql/16/main/pg_hba.conf << 'PGHBACONF'
${local.pg_hba_config}
PGHBACONF

# Set ownership
chown postgres:postgres /etc/postgresql/16/main/postgresql.conf
chown postgres:postgres /etc/postgresql/16/main/pg_hba.conf
chmod 640 /etc/postgresql/16/main/postgresql.conf
chmod 640 /etc/postgresql/16/main/pg_hba.conf

# Create log directory
mkdir -p /var/log/postgresql
chown postgres:postgres /var/log/postgresql

# Start PostgreSQL
systemctl start postgresql && systemctl enable postgresql
sleep 5

# Set postgres user password
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD';"

# Create application database
sudo -u postgres psql -c "CREATE DATABASE ${var.pgsql_database};"

# Create application user
PGSQL_USER_PASSWORD=$(aws secretsmanager get-secret-value --secret-id ${aws_secretsmanager_secret.pgsql_user_password.name} --region ${data.aws_region.current.name} --query SecretString --output text)
sudo -u postgres psql -c "CREATE USER ${var.pgsql_user} WITH PASSWORD '$PGSQL_USER_PASSWORD';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${var.pgsql_database} TO ${var.pgsql_user};"
sudo -u postgres psql -d ${var.pgsql_database} -c "GRANT ALL ON SCHEMA public TO ${var.pgsql_user};"

%{~ if var.enable_cloudwatch_monitoring ~}
# Install CloudWatch agent
if [ ! -x /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent ]; then
  CW_DEB=/tmp/amazon-cloudwatch-agent.deb
  wget -q -O "$CW_DEB" \
    https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/arm64/latest/amazon-cloudwatch-agent.deb
  dpkg -i "$CW_DEB"
fi
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CWCFG'
{"logs":{"logs_collected":{"files":{"collect_list":[{"file_path":"/var/log/postgresql/postgresql-*.log","log_group_name":"${try(aws_cloudwatch_log_group.pgsql_logs[0].name, "")}","log_stream_name":"{instance_id}/postgres"},{"file_path":"/var/log/pgsql-setup.log","log_group_name":"${try(aws_cloudwatch_log_group.pgsql_logs[0].name, "")}","log_stream_name":"{instance_id}/setup"}]}}},"metrics":{"namespace":"PostgreSQL/EC2","metrics_collected":{"cpu":{"measurement":[{"name":"cpu_usage_idle"}]},"disk":{"measurement":[{"name":"used_percent"}],"resources":["*"]},"mem":{"measurement":[{"name":"mem_used_percent"}]}}}}
CWCFG
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json
%{~ endif ~}


%{~ if var.enable_automated_backups && local.backup_bucket_name != "" ~}

# Backup script
cat > /usr/local/bin/backup_pgsql.sh << 'BACKUP'

#!/bin/bash

TODAY=$(date +"%Y-%m-%d")
TIME=$(date +"%H%M%S")

# Get Postgres password from AWS Secrets Manager
POSTGRES_PASSWORD=$(aws secretsmanager get-secret-value \
    --secret-id ${aws_secretsmanager_secret.pgsql_postgres_password.name} \
    --region ${data.aws_region.current.name} \
    --query SecretString --output text)

export PGPASSWORD="$POSTGRES_PASSWORD"

# Database connection info
DB_HOST=0.0.0.0
DB_PORT=5432
DB_USERNAME=postgres
DB_DATABASE=${var.pgsql_database}

# Backup and compress in one step
pg_dump --no-owner --no-privileges -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_DATABASE" | gzip > /tmp/${TIME}-${DB_DATABASE}.sql.gz

# Upload to S3
aws s3 cp /tmp/${TIME}-${DB_DATABASE}.sql.gz s3://${local.backup_bucket_name}/$TODAY/

# Remove local dump
rm /tmp/${TIME}-${DB_DATABASE}.sql.gz

echo "Backup completed for $DB_DATABASE on $TODAY"
BACKUP

chmod +x /usr/local/bin/backup_pgsql.sh
echo "${var.backup_schedule} /usr/local/bin/backup_pgsql.sh >> /var/log/pgsql-backup.log 2>&1" | crontab -
/usr/local/bin/backup_pgsql.sh  # Initial backup
%{~ endif ~}

echo "=== PostgreSQL Setup Complete: $(date) ==="
EOF
}

