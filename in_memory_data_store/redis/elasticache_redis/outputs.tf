################################################################################
# Outputs for ElastiCache Redis Module
################################################################################

output "elasticache" {
  description = "Complete ElastiCache cluster configuration and connection details"
  value = {
    # Cluster enabled status
    enabled = var.enable_elasticache

    # Cluster type (single node or replication group)
    cluster_type = var.enable_elasticache ? (var.num_cache_nodes > 1 ? "replication-group" : "single-node") : null

    # Connection details
    connection = var.enable_elasticache ? {
      # Primary endpoint (for writes)
      primary_endpoint = var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address

      # Reader endpoint (for reads in HA setup)
      reader_endpoint = var.num_cache_nodes > 1 && var.automatic_failover_enabled ? aws_elasticache_replication_group.main[0].reader_endpoint_address : null

      # Configuration endpoint (for cluster mode)
      configuration_endpoint = var.num_cache_nodes > 1 && var.cluster_mode_enabled ? aws_elasticache_replication_group.main[0].configuration_endpoint_address : null

      # Port
      port = var.port

      # Full endpoint string
      endpoint = var.num_cache_nodes > 1 ? "${aws_elasticache_replication_group.main[0].primary_endpoint_address}:${var.port}" : "${aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}"

      # Password required
      password_required = var.auth_token != ""

      # TLS/SSL required
      tls_enabled = var.transit_encryption_enabled

      # Connection string examples
      redis_cli_command = var.auth_token != "" && var.transit_encryption_enabled ? "redis-cli -h ${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address} -p ${var.port} --tls -a '***PASSWORD***'" : var.auth_token != "" ? "redis-cli -h ${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address} -p ${var.port} -a '***PASSWORD***'" : "redis-cli -h ${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address} -p ${var.port}"

      node_js_url = var.auth_token != "" ? "redis://:***PASSWORD***@${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}" : "redis://${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}"

      python_url = var.auth_token != "" ? "redis://:***PASSWORD***@${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}/0" : "redis://${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}/0"
    } : null

    # Cluster configuration
    configuration = var.enable_elasticache ? {
      engine               = var.engine
      engine_version       = var.engine_version
      node_type            = var.node_type
      num_cache_nodes      = var.num_cache_nodes
      cluster_mode_enabled = var.cluster_mode_enabled
      num_node_groups      = var.cluster_mode_enabled ? var.num_node_groups : null
      replicas_per_node_group = var.cluster_mode_enabled ? var.replicas_per_node_group : null
      parameter_group_name = aws_elasticache_parameter_group.main[0].name
    } : null

    # High Availability settings
    high_availability = var.enable_elasticache ? {
      enabled                    = var.num_cache_nodes > 1
      automatic_failover_enabled = var.automatic_failover_enabled
      multi_az_enabled           = var.multi_az_enabled
      num_cache_nodes            = var.num_cache_nodes
      failover_time              = var.automatic_failover_enabled ? "30-60 seconds" : "N/A (manual restart required)"
    } : null

    # Security settings
    security = var.enable_elasticache ? {
      security_group_id          = aws_security_group.elasticache[0].id
      security_group_name        = aws_security_group.elasticache[0].name
      at_rest_encryption_enabled = var.at_rest_encryption_enabled
      transit_encryption_enabled = var.transit_encryption_enabled
      auth_token_set             = var.auth_token != ""
    } : null

    # Backup settings
    backup = var.enable_elasticache ? {
      enabled                  = var.snapshot_retention_limit > 0
      snapshot_retention_limit = var.snapshot_retention_limit
      snapshot_window          = var.snapshot_window
      final_snapshot_enabled   = var.final_snapshot_identifier != ""
    } : null

    # Maintenance settings
    maintenance = var.enable_elasticache ? {
      maintenance_window         = var.maintenance_window
      auto_minor_version_upgrade = var.auto_minor_version_upgrade
    } : null

    # Resource identifiers
    identifiers = var.enable_elasticache ? {
      cluster_id           = var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].id : aws_elasticache_cluster.main[0].id
      replication_group_id = var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].replication_group_id : null
      subnet_group_name    = aws_elasticache_subnet_group.main[0].name
      parameter_group_name = aws_elasticache_parameter_group.main[0].name
      arn                  = var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].arn : aws_elasticache_cluster.main[0].arn
    } : null

    # Cost estimate
    estimated_cost = var.enable_elasticache ? {
      node_type        = var.node_type
      num_nodes        = var.num_cache_nodes
      monthly_estimate = var.engine == "valkey" ? (
        var.node_type == "cache.t4g.micro" ? "${var.num_cache_nodes * 14}-${var.num_cache_nodes * 18}/month" :
        var.node_type == "cache.t4g.small" ? "${var.num_cache_nodes * 28}-${var.num_cache_nodes * 36}/month" :
        var.node_type == "cache.t4g.medium" ? "${var.num_cache_nodes * 56}-${var.num_cache_nodes * 72}/month" :
        "Contact AWS for pricing"
      ) : (
        var.node_type == "cache.t4g.micro" ? "${var.num_cache_nodes * 20}-${var.num_cache_nodes * 25}/month" :
        var.node_type == "cache.t4g.small" ? "${var.num_cache_nodes * 40}-${var.num_cache_nodes * 50}/month" :
        var.node_type == "cache.t4g.medium" ? "${var.num_cache_nodes * 80}-${var.num_cache_nodes * 100}/month" :
        "Contact AWS for pricing"
      )
      note = "Valkey is 30% cheaper than Redis OSS. Add data transfer costs if applicable."
    } : {
      monthly_estimate = "$0 (ElastiCache disabled)"
    }

    # Application configuration examples
    app_config_examples = var.enable_elasticache ? {
      node_js = {
        package    = "ioredis"
        install    = "npm install ioredis"
        connection = var.transit_encryption_enabled ? <<-EOF
          const Redis = require('ioredis');
          const redis = new Redis({
            host: '${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}',
            port: ${var.port},
            ${var.auth_token != "" ? "password: process.env.REDIS_PASSWORD," : ""}
            tls: {
              checkServerIdentity: () => undefined
            },
            retryStrategy: (times) => Math.min(times * 50, 2000)
          });
        EOF
        : <<-EOF
          const Redis = require('ioredis');
          const redis = new Redis({
            host: '${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}',
            port: ${var.port},
            ${var.auth_token != "" ? "password: process.env.REDIS_PASSWORD," : ""}
            retryStrategy: (times) => Math.min(times * 50, 2000)
          });
        EOF
      }
      python = {
        package    = "redis"
        install    = "pip install redis"
        connection = var.transit_encryption_enabled ? <<-EOF
          import redis
          r = redis.Redis(
              host='${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}',
              port=${var.port},
              ${var.auth_token != "" ? "password=os.environ['REDIS_PASSWORD']," : ""}
              ssl=True,
              ssl_cert_reqs=None,
              decode_responses=True
          )
        EOF
        : <<-EOF
          import redis
          r = redis.Redis(
              host='${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}',
              port=${var.port},
              ${var.auth_token != "" ? "password=os.environ['REDIS_PASSWORD']," : ""}
              decode_responses=True
          )
        EOF
      }
      environment_variables = {
        REDIS_HOST     = var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address
        REDIS_PORT     = tostring(var.port)
        REDIS_PASSWORD = var.auth_token != "" ? "***SET_IN_ENV***" : ""
        REDIS_TLS      = var.transit_encryption_enabled ? "true" : "false"
        REDIS_URL      = var.auth_token != "" ? "redis://:***PASSWORD***@${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}" : "redis://${var.num_cache_nodes > 1 ? aws_elasticache_replication_group.main[0].primary_endpoint_address : aws_elasticache_cluster.main[0].cache_nodes[0].address}:${var.port}"
      }
    } : null
  }

  sensitive = false
}

# Separate sensitive output for auth token (if needed)
output "redis_auth_token" {
  description = "Redis AUTH token (sensitive - only shown if explicitly queried)"
  value       = var.enable_elasticache && var.auth_token != "" ? var.auth_token : null
  sensitive   = true
}

