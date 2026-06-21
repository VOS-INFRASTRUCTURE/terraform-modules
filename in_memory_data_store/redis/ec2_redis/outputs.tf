################################################################################
# Outputs for EC2 Redis Module
################################################################################

output "redis" {
  description = "Complete EC2 Redis instance configuration and connection details"
  value = {

    # EC2 Instance details
    instance = {
      id                = aws_instance.redis[0].id
      arn               = aws_instance.redis[0].arn
      instance_type     = aws_instance.redis[0].instance_type
      availability_zone = aws_instance.redis[0].availability_zone
      private_ip        = aws_instance.redis[0].private_ip
      public_ip         = aws_instance.redis[0].public_ip
      state             = aws_instance.redis[0].instance_state
    }

    # Redis connection details
    connection = {
      host              = aws_instance.redis[0].private_ip
      port              = var.redis_port
      endpoint          = "${aws_instance.redis[0].private_ip}:${var.redis_port}"
      password_required = var.redis_password != ""

      redis_cli_command = var.redis_password != "" ? "redis-cli -h ${aws_instance.redis[0].private_ip} -p ${var.redis_port} -a '***PASSWORD***'" : "redis-cli -h ${aws_instance.redis[0].private_ip} -p ${var.redis_port}"
      node_js_url       = var.redis_password != "" ? "redis://:***PASSWORD***@${aws_instance.redis[0].private_ip}:${var.redis_port}" : "redis://${aws_instance.redis[0].private_ip}:${var.redis_port}"
      python_url        = var.redis_password != "" ? "redis://:***PASSWORD***@${aws_instance.redis[0].private_ip}:${var.redis_port}/0" : "redis://${aws_instance.redis[0].private_ip}:${var.redis_port}/0"
    }

    # Redis configuration
    configuration = {
      version         = var.redis_version
      max_memory      = local.redis_max_memory
      eviction_policy = var.redis_max_memory_policy
      persistence     = var.enable_redis_persistence
      aof_enabled     = var.enable_redis_aof
      password_set    = var.redis_password != ""
    }

    # IAM Role
    iam_role = {
      name = aws_iam_role.redis[0].name
      arn  = aws_iam_role.redis[0].arn
    }

    # Monitoring
    monitoring = {
      cloudwatch_enabled = var.enable_cloudwatch_monitoring
      cloudwatch_logs    = var.enable_cloudwatch_logs
      log_group_name     = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redis[0].name : null
      log_group_arn      = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.redis[0].arn : null
      ssm_access_enabled = var.enable_ssm_access
    }

    # Cost estimate
    estimated_cost = {
      instance_type    = var.instance_type
      monthly_estimate = var.instance_type == "t4g.nano" ? "$3-4/month" : var.instance_type == "t4g.micro" ? "$7-8/month" : var.instance_type == "t4g.small" ? "$14-16/month" : "$28-32/month"
      breakdown = {
        ec2_instance  = var.instance_type == "t4g.nano" ? "$3/month" : var.instance_type == "t4g.micro" ? "$6.50/month" : var.instance_type == "t4g.small" ? "$13/month" : "$26/month"
        ebs_storage   = "${var.root_volume_size} GB × $0.10/GB = $${var.root_volume_size * 0.10}/month"
        data_transfer = "$0-1/month (minimal)"
        cloudwatch    = var.enable_cloudwatch_monitoring || var.enable_cloudwatch_logs ? "$0.50-1/month" : "$0/month"
      }
    }

    # Access instructions
    access = {
      ssm_session          = var.enable_ssm_access ? "aws ssm start-session --target ${aws_instance.redis[0].id}" : "SSM access not enabled"
      ssh_command          = var.enable_ssh_key_access ? "ssh -i /path/to/${var.key_name}.pem ubuntu@${aws_instance.redis[0].private_ip}" : "SSH key not configured"
      redis_cli            = "After connecting to instance: redis-cli${var.redis_password != "" ? " -a 'YOUR_PASSWORD'" : ""}"
      health_check_command = var.redis_password != "" ? "redis-cli -h ${aws_instance.redis[0].private_ip} -p ${var.redis_port} -a 'YOUR_PASSWORD' ping" : "redis-cli -h ${aws_instance.redis[0].private_ip} -p ${var.redis_port} ping"
    }

    # Application configuration examples
    app_config_examples = {
      node_js = {
        package    = "ioredis"
        install    = "npm install ioredis"
        connection = <<-EOF
          const Redis = require('ioredis');
          const redis = new Redis({
            host: '${aws_instance.redis[0].private_ip}',
            port: ${var.redis_port},
            ${var.redis_password != "" ? "password: process.env.REDIS_PASSWORD," : ""}
            retryStrategy: (times) => Math.min(times * 50, 2000)
          });
        EOF
      }
      python = {
        package    = "redis"
        install    = "pip install redis"
        connection = <<-EOF
          import redis
          r = redis.Redis(
              host='${aws_instance.redis[0].private_ip}',
              port=${var.redis_port},
              ${var.redis_password != "" ? "password=os.environ['REDIS_PASSWORD']," : ""}
              decode_responses=True
          )
        EOF
      }
      php = {
        package    = "predis/predis"
        install    = "composer require predis/predis"
        connection = <<-EOF
          $redis = new Predis\\Client([
              'scheme' => 'tcp',
              'host'   => '${aws_instance.redis[0].private_ip}',
              'port'   => ${var.redis_port},
              ${var.redis_password != "" ? "'password' => getenv('REDIS_PASSWORD')," : ""}
          ]);
        EOF
      }
      environment_variables = {
        REDIS_HOST     = aws_instance.redis[0].private_ip
        REDIS_PORT     = tostring(var.redis_port)
        REDIS_PASSWORD = var.redis_password != "" ? "***SET_IN_ENV***" : ""
        REDIS_URL      = var.redis_password != "" ? "redis://:***PASSWORD***@${aws_instance.redis[0].private_ip}:${var.redis_port}" : "redis://${aws_instance.redis[0].private_ip}:${var.redis_port}"
      }
    }
  }

  sensitive = false
}

output "redis_password" {
  description = "Redis password (sensitive - only shown if explicitly queried)"
  value       = var.redis_password != "" ? var.redis_password : null
  sensitive   = true
}
