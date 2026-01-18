################################################################################
# ElastiCache Redis/Valkey Module
#
# Purpose: Deploy managed Redis/Valkey cluster on AWS ElastiCache
#
# What This Module Does:
# - Creates ElastiCache cluster (single node or HA with replicas)
# - Configures security groups for network access
# - Sets up subnet groups for Multi-AZ deployment
# - Configures parameter groups for Redis/Valkey tuning
# - Optional: Automatic backups and snapshots
# - Optional: Encryption at rest and in transit
# - Optional: Multi-AZ with automatic failover
#
# Cost: ~$14-18/month for cache.t4g.micro (1 node)
#       ~$28-36/month for cache.t4g.micro (2 nodes HA)
#
# Use Cases:
# - Production applications requiring high availability
# - Managed service with automatic failover
# - Applications needing minimal ops overhead
# - Compliance requirements (encryption, backups)
#
# Advantages over EC2 Redis:
# - Automatic failover (if HA enabled)
# - Automatic backups
# - Automatic patching
# - Built-in monitoring
# - Multi-AZ support
# - No OS management
#
# Recommendation: Use Valkey engine (30% cheaper than Redis OSS)
################################################################################


################################################################################
# ElastiCache Subnet Group
################################################################################

resource "aws_elasticache_subnet_group" "main" {
  count = var.enable_elasticache ? 1 : 0

  name        = "${var.env}-${var.project_id}-elasticache-subnet-group"
  description = "Subnet group for ElastiCache ${var.engine} cluster"
  subnet_ids  = var.subnet_ids

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-elasticache-subnet-group"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "ElastiCache-SubnetGroup"
    },
    var.tags
  )
}

################################################################################
# ElastiCache Parameter Group
################################################################################

resource "aws_elasticache_parameter_group" "main" {
  count = var.enable_elasticache ? 1 : 0

  name        = "${var.env}-${var.project_id}-${var.engine}-params"
  family      = var.parameter_group_family
  description = "Custom parameter group for ${var.engine} cluster"

  # Apply custom parameters if provided
  dynamic "parameter" {
    for_each = var.custom_parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-${var.engine}-params"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "ElastiCache-ParameterGroup"
    },
    var.tags
  )
}

################################################################################
# ElastiCache Replication Group (for HA setup)
################################################################################

resource "aws_elasticache_replication_group" "main" {
  count = var.enable_elasticache && var.num_cache_nodes > 1 ? 1 : 0

  replication_group_id = "${var.env}-${var.project_id}-${var.engine}"
  description          = "${var.env} ${var.project_id} ${var.engine} cluster"

  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.main[0].name

  # High Availability Configuration
  num_cache_clusters         = var.num_cache_nodes
  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  # Network Configuration
  subnet_group_name  = aws_elasticache_subnet_group.main[0].name
  security_group_ids = [aws_security_group.elasticache[0].id]

  # Security Configuration
  at_rest_encryption_enabled = var.at_rest_encryption_enabled
  transit_encryption_enabled = var.transit_encryption_enabled
  auth_token                 = var.auth_token != "" ? var.auth_token : null
  auth_token_update_strategy = var.auth_token != "" ? var.auth_token_update_strategy : null

  # Backup Configuration
  snapshot_retention_limit  = var.snapshot_retention_limit
  snapshot_window           = var.snapshot_window
  final_snapshot_identifier = var.final_snapshot_identifier != "" ? "${var.env}-${var.project_id}-final-${formatdate("YYYYMMDD-hhmm", timestamp())}" : null

  # Maintenance Configuration
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Notifications
  notification_topic_arn = var.notification_topic_arn != "" ? var.notification_topic_arn : null

  # Log Delivery Configuration
  dynamic "log_delivery_configuration" {
    for_each = var.log_delivery_configuration
    content {
      destination      = log_delivery_configuration.value.destination
      destination_type = log_delivery_configuration.value.destination_type
      log_format       = log_delivery_configuration.value.log_format
      log_type         = log_delivery_configuration.value.log_type
    }
  }

  tags = merge(
    {
      Name             = "${var.env}-${var.project_id}-${var.engine}-cluster"
      Environment      = var.env
      Project          = var.project_id
      ManagedBy        = "Terraform"
      Purpose          = "ElastiCache-ReplicationGroup"
      Engine           = var.engine
      HighAvailability = var.automatic_failover_enabled ? "Enabled" : "Disabled"
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

################################################################################
# ElastiCache Cluster (for single node setup)
################################################################################

resource "aws_elasticache_cluster" "main" {
  count = var.enable_elasticache && var.num_cache_nodes == 1 ? 1 : 0

  cluster_id           = "${var.env}-${var.project_id}-${var.engine}"
  engine               = var.engine
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_nodes      = 1
  port                 = var.port
  parameter_group_name = aws_elasticache_parameter_group.main[0].name

  # Network Configuration
  subnet_group_name  = aws_elasticache_subnet_group.main[0].name
  security_group_ids = [aws_security_group.elasticache[0].id]

  # Backup Configuration
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window          = var.snapshot_window
  final_snapshot_identifier = var.final_snapshot_identifier != "" ? "${var.env}-${var.project_id}-final-${formatdate("YYYYMMDD-hhmm", timestamp())}" : null

  # Maintenance Configuration
  maintenance_window         = var.maintenance_window
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  # Notifications
  notification_topic_arn = var.notification_topic_arn != "" ? var.notification_topic_arn : null

  # Log Delivery Configuration
  dynamic "log_delivery_configuration" {
    for_each = var.log_delivery_configuration
    content {
      destination      = log_delivery_configuration.value.destination
      destination_type = log_delivery_configuration.value.destination_type
      log_format       = log_delivery_configuration.value.log_format
      log_type         = log_delivery_configuration.value.log_type
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-${var.engine}-cluster"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "ElastiCache-Cluster"
      Engine      = var.engine
      HighAvailability = "Disabled"
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

