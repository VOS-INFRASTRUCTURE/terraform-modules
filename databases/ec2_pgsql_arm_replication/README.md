# EC2 PostgreSQL ARM Module (Native Installation)

Production-ready PostgreSQL 15 on AWS EC2 ARM (Graviton) instances with native installation for maximum performance and cost efficiency.

## 🎯 Features

- ✅ **PostgreSQL 15** - Latest stable version
- ✅ **Native ARM Installation** - No Docker overhead, 5-10% faster
- ✅ **AWS Graviton (ARM)** - 20-25% cost savings vs x86
- ✅ **Automated Backups** - Hourly pg_dumpall to S3 + optional EBS snapshots
- ✅ **Secrets Manager** - Passwords never in plaintext
- ✅ **CloudWatch Monitoring** - Logs and metrics
- ✅ **Session Manager Access** - No SSH keys needed
- ✅ **Production Optimized** - Tuned PostgreSQL configuration
- ✅ **Cross-Region DR** - Optional snapshot copy for disaster recovery

## 📦 What You Get

| Component | Details |
|-----------|---------|
| **Instance** | m7g.large (2 vCPU, 8GB RAM) - $67/month default |
| **PostgreSQL** | Version 15 with optimized config |
| **Storage** | 20GB gp3 EBS (encrypted) |
| **Backups** | Hourly to S3 (7 days retention) |
| **Monitoring** | CloudWatch logs and metrics |
| **Security** | Secrets Manager, IAM, encryption |
| **Access** | Systems Manager Session Manager |

## 🚀 Quick Start

### Minimal Configuration

```hcl
module "postgres" {
  source = "../../databases/ec2_pgsql_arm"
  
  env        = "production"
  project_id = "myapp"
  
  # Network
  subnet_id          = "subnet-xxxxx"
  security_group_ids = ["sg-xxxxx"]  # Must allow PostgreSQL port 5432
  
  # PostgreSQL
  pgsql_database = "myapp_db"
  pgsql_user     = "myapp_user"
}
```

### Full Configuration

```hcl
module "postgres" {
  source = "../../databases/ec2_pgsql_arm"
  
  # Environment
  env        = "production"
  project_id = "myapp"
  base_name  = "db"  # Optional, default: "pgsql"
  
  # Instance
  instance_type = "m7g.large"  # 2 vCPU, 8GB RAM
  ami_id        = ""           # Auto-detect Ubuntu 24.04 ARM64
  
  # Network
  subnet_id          = "subnet-xxxxx"
  security_group_ids = ["sg-xxxxx"]
  
  # Storage
  storage_size           = 20
  storage_type           = "gp3"
  enable_ebs_encryption  = true
  
  # PostgreSQL Configuration
  pgsql_database       = "myapp_db"
  pgsql_user           = "myapp_user"
  shared_buffers       = "2GB"   # 25% of RAM
  effective_cache_size = "6GB"   # 75% of RAM
  max_connections      = 200
  
  # Backups
  enable_automated_backups = true
  backup_schedule          = "0 * * * *"  # Hourly
  backup_retention_days    = 7
  create_backup_bucket     = true
  
  # EBS Snapshots (Optional)
  enable_ebs_snapshots = true
  ebs_snapshot_time    = "03:00"
  ebs_snapshot_retention_count = 7
  
  # Cross-Region DR (Optional)
  enable_cross_region_snapshot_copy = true
  snapshot_dr_region                = "us-east-1"
  snapshot_dr_retention_days        = 7
  
  # Monitoring
  enable_cloudwatch_monitoring = true
  cloudwatch_retention_days    = 90
  
  # Security
  enable_termination_protection = true
  
  tags = {
    Team = "Backend"
  }
}
```

## 📊 Outputs

```hcl
output "postgres_connection" {
  value = module.postgres.pgsql.connection
}

output "postgres_instance" {
  value = module.postgres.pgsql.instance
}
```

### Available Outputs

```bash
# Get all outputs
terraform output -json postgres | jq

# Connection details
terraform output -json postgres | jq '.connection'

# Instance details
terraform output -json postgres | jq '.instance'

# Get passwords from Secrets Manager
terraform output -raw postgres_password_retrieval | bash
terraform output -raw user_password_retrieval | bash
```

## 🔐 Security

### Passwords

Passwords are automatically generated and stored in AWS Secrets Manager:

```bash
# Retrieve postgres superuser password
aws secretsmanager get-secret-value \
  --secret-id production/myapp/pgsql/pgsql-postgres-password \
  --query SecretString --output text

# Retrieve application user password
aws secretsmanager get-secret-value \
  --secret-id production/myapp/pgsql/pgsql-user-password \
  --query SecretString --output text
```

### Access Instance

```bash
# Via Session Manager (recommended - no SSH keys needed)
aws ssm start-session --target i-instanceid

# Then connect to PostgreSQL
sudo -u postgres psql
# or
psql -h localhost -U myapp_user -d myapp_db
```

### Security Groups

Your security group must allow:
- **PostgreSQL**: Port 5432 (from your application subnets)
- **Session Manager**: No inbound rules needed (uses AWS SSM)

## 💾 Backups

### S3 Backups (Default)

**What:** Full database dump using `pg_dumpall`  
**Schedule:** Hourly (configurable)  
**Retention:** 7 days (configurable)  
**Format:** Compressed SQL (.sql.gz)  

**S3 Structure:**
```
s3://bucket/pgsql-backups/production/myapp/
├── 2026-01-22/
│   ├── 010000-all-databases.sql.gz
│   ├── 020000-all-databases.sql.gz
│   └── 030000-all-databases.sql.gz
└── 2026-01-23/
    └── ...
```

### EBS Snapshots (Optional)

**What:** Volume-level snapshot  
**Schedule:** Daily at 3 AM UTC  
**Retention:** 7 snapshots  
**Cost:** ~$1.70/month (20GB, 7 snapshots)

### Restore from S3 Backup

```bash
# 1. List backups
aws s3 ls s3://bucket/pgsql-backups/production/myapp/ --recursive

# 2. Download
aws s3 cp s3://bucket/.../020000-all-databases.sql.gz .

# 3. Extract
gunzip 020000-all-databases.sql.gz

# 4. Connect to instance
aws ssm start-session --target i-instanceid

# 5. Restore
sudo -u postgres psql < 020000-all-databases.sql
```

## 💰 Cost Breakdown

### Standard Setup (m7g.large)

| Component | Monthly Cost |
|-----------|--------------|
| EC2 m7g.large (ARM) | $67.15 |
| EBS (20GB gp3) | $1.60 |
| S3 backups | $0.64 |
| Secrets Manager | $0.80 |
| CloudWatch Logs | $2.50 |
| **Total** | **~$72.69/month** |

### With EBS Snapshots

| Component | Monthly Cost |
|-----------|--------------|
| Standard Setup | $72.69 |
| EBS Snapshots (7 × 20GB) | $1.70 |
| **Total** | **~$74.39/month** |

### With Cross-Region DR

| Component | Monthly Cost |
|-----------|--------------|
| Standard + Snapshots | $74.39 |
| DR Snapshots (7 × 20GB) | $1.70 |
| Data Transfer (one-time) | $0.18 |
| **Total** | **~$76.27/month** |

**Savings vs x86:** ~$21/month ($252/year)

## ⚙️ PostgreSQL Configuration

The module applies production-optimized PostgreSQL settings:

### Memory Settings (for m7g.large - 8GB RAM)

```ini
shared_buffers = 2GB           # 25% of RAM
effective_cache_size = 6GB     # 75% of RAM
maintenance_work_mem = 512MB
work_mem = 16MB
```

### Connection Settings

```ini
max_connections = 200
listen_addresses = '*'
port = 5432
```

### Performance Tuning

```ini
random_page_cost = 1.1         # Optimized for SSD
effective_io_concurrency = 200
checkpoint_completion_target = 0.9
wal_buffers = 16MB
```

### Security

```ini
password_encryption = scram-sha-256
ssl = on
```

### Customization

Adjust these variables for different instance sizes:

```hcl
# For m7g.xlarge (16GB RAM)
shared_buffers       = "4GB"   # 25% of 16GB
effective_cache_size = "12GB"  # 75% of 16GB

# For r7g.large (16GB RAM, memory-optimized)
shared_buffers       = "4GB"
effective_cache_size = "12GB"
max_connections      = 300
```

## 📈 Monitoring

### CloudWatch Metrics

- CPU usage
- Memory usage
- Disk usage
- Network I/O

### CloudWatch Logs

- PostgreSQL server logs
- Slow query logs
- Backup logs
- Setup logs

### Viewing Logs

```bash
# Via AWS Console
CloudWatch → Log Groups → /aws/ec2/myapp-production-pgsql

# Via CLI
aws logs tail /aws/ec2/myapp-production-pgsql --follow
```

## 🔄 Maintenance

### Update PostgreSQL Configuration

1. Edit `postgresql.conf` template
2. Apply changes: `terraform apply`
3. Restart PostgreSQL:
   ```bash
   aws ssm start-session --target i-instanceid
   sudo systemctl restart postgresql
   ```

### Scale Instance Size

```hcl
module "postgres" {
  source = "../../databases/ec2_pgsql_arm"
  
  instance_type        = "m7g.xlarge"  # Upgrade from m7g.large
  shared_buffers       = "4GB"         # Adjust for new RAM
  effective_cache_size = "12GB"
  
  # ...other config
}
```

Then:
```bash
terraform apply
# Instance will be recreated with larger size
# Restore from latest backup if needed
```

## 🌐 Instance Type Options

### Burstable (Development/Staging)

| Instance | vCPU | RAM | Monthly Cost | Use Case |
|----------|------|-----|--------------|----------|
| t4g.micro | 2 | 1GB | $6.13 | Testing |
| t4g.small | 2 | 2GB | $12.26 | Development |
| t4g.medium | 2 | 4GB | $24.53 | Staging |
| t4g.large | 2 | 8GB | $49.06 | Small production |

### General Purpose (Production)

| Instance | vCPU | RAM | Monthly Cost | Use Case |
|----------|------|-----|--------------|----------|
| m7g.large | 2 | 8GB | $67.15 | ⭐ Default production |
| m7g.xlarge | 4 | 16GB | $134.30 | Large production |
| m7g.2xlarge | 8 | 32GB | $268.59 | High traffic |

### Memory Optimized (Large Databases)

| Instance | vCPU | RAM | Monthly Cost | Use Case |
|----------|------|-----|--------------|----------|
| r7g.large | 2 | 16GB | $83.95 | Memory-heavy |
| r7g.xlarge | 4 | 32GB | $167.90 | Large datasets |

## 🆚 PostgreSQL vs MySQL

| Feature | PostgreSQL | MySQL |
|---------|-----------|-------|
| **ACID Compliance** | ✅ Full | ✅ Full (InnoDB) |
| **JSON Support** | ✅ Better (JSONB) | ⚠️ Basic |
| **Advanced Queries** | ✅ CTEs, Window Functions | ⚠️ Limited |
| **Full Text Search** | ✅ Built-in | ❌ Requires plugin |
| **Replication** | ✅ Streaming | ✅ Binary log |
| **Extensions** | ✅ PostGIS, pgvector | ⚠️ Limited |
| **Performance** | ✅ Complex queries | ✅ Simple queries |
| **Ecosystem** | ✅ Django, Rails | ✅ Laravel, WordPress |

## 📚 Additional Documentation

- [PostgreSQL 15 Release Notes](https://www.postgresql.org/docs/15/release-15.html)
- [AWS Graviton Performance](https://aws.amazon.com/ec2/graviton/)
- [PostgreSQL Best Practices](https://wiki.postgresql.org/wiki/Performance_Optimization)

## ⚠️ Important Notes

1. **First Deployment**: Takes ~5-10 minutes for PostgreSQL installation
2. **Passwords**: Auto-generated on first deployment, stored in Secrets Manager
3. **Security Groups**: Must allow port 5432 from your application
4. **Backups**: First backup runs immediately after installation
5. **AMI**: Auto-detects latest Ubuntu 24.04 ARM64 for your region
6. **User Data**: Changes don't trigger instance replacement (use `terraform taint` if needed)

## 🐛 Troubleshooting

### Check PostgreSQL Status

```bash
aws ssm start-session --target i-instanceid
sudo systemctl status postgresql
sudo -u postgres psql -c "SELECT version();"
```

### View Setup Logs

```bash
sudo cat /var/log/pgsql-setup.log
```

### View PostgreSQL Logs

```bash
sudo tail -f /var/log/postgresql/postgresql-*.log
```

### Connection Issues

```bash
# Test from EC2
psql -h localhost -U myapp_user -d myapp_db

# Check if PostgreSQL is listening
sudo netstat -tulpn | grep 5432

# Check pg_hba.conf
sudo cat /etc/postgresql/15/main/pg_hba.conf
```

### Backup Issues

```bash
# Check backup logs
sudo cat /var/log/pgsql-backup.log

# Run manual backup
sudo /usr/local/bin/backup_pgsql.sh

# List S3 backups
aws s3 ls s3://bucket/pgsql-backups/production/myapp/ --recursive
```

## 📝 Example Use Cases

### Web Application Database

```hcl
module "app_db" {
  source = "../../databases/ec2_pgsql_arm"
  
  env        = "production"
  project_id = "webapp"
  
  instance_type  = "m7g.large"
  pgsql_database = "webapp_db"
  pgsql_user     = "webapp_user"
  
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids = [aws_security_group.db.id]
  
  enable_automated_backups = true
  backup_schedule          = "0 */6 * * *"  # Every 6 hours
}
```

### Analytics Database

```hcl
module "analytics_db" {
  source = "../../databases/ec2_pgsql_arm"
  
  env        = "production"
  project_id = "analytics"
  
  instance_type        = "r7g.large"  # Memory-optimized
  storage_size         = 100
  shared_buffers       = "4GB"
  effective_cache_size = "12GB"
  max_connections      = 100
  
  pgsql_database = "analytics_db"
  pgsql_user     = "analyst"
  
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids = [aws_security_group.db.id]
}
```

## 🔒 Production Checklist

- [ ] Security group allows only necessary inbound traffic
- [ ] Instance in private subnet
- [ ] Termination protection enabled
- [ ] Automated backups enabled
- [ ] CloudWatch monitoring enabled
- [ ] EBS encryption enabled
- [ ] Secrets rotation configured (optional)
- [ ] Cross-region DR snapshots (for critical data)
- [ ] Monitoring alerts configured
- [ ] Backup restore tested

## 📞 Support

For issues or questions:
1. Check [troubleshooting section](#-troubleshooting)
2. Review CloudWatch logs
3. Check PostgreSQL error logs
4. Open GitHub issue with details

---

**Last Updated:** January 22, 2026  
**Module Version:** 1.0.0  
**PostgreSQL Version:** 15  
**Tested On:** Ubuntu 24.04 LTS ARM64

