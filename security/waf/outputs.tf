################################################################################
# AWS WAF Module Outputs
#
# All outputs are consolidated into a single 'waf' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.waf.waf.web_acl.id
#   module.waf.waf.logging.bucket_name
#   module.waf.waf.summary.total_wcu_used
################################################################################

output "waf" {
  description = "AWS WAF resources and configuration details"
  value = var.enable_waf ? {
    # ──────────────────────────────────────────────────────────────────────
    # Web ACL - Main WAF resource
    # ──────────────────────────────────────────────────────────────────────
    web_acl = {
      id          = aws_wafv2_web_acl.waf[0].id                    # Web ACL ID
      arn         = aws_wafv2_web_acl.waf[0].arn                   # Web ACL ARN
      name        = aws_wafv2_web_acl.waf[0].name                  # Web ACL name
      capacity    = aws_wafv2_web_acl.waf[0].capacity              # Current WCU usage
      scope       = var.waf_scope                                       # REGIONAL or CLOUDFRONT
      description = aws_wafv2_web_acl.waf[0].description          # Web ACL description
    }

    # ──────────────────────────────────────────────────────────────────────
    # Association - ALB/CloudFront association
    # ──────────────────────────────────────────────────────────────────────
    association = var.alb_arn != null ? {
      resource_arn = aws_wafv2_web_acl_association.alb_waf_assoc[0].resource_arn  # Associated resource ARN
      web_acl_arn  = aws_wafv2_web_acl_association.alb_waf_assoc[0].web_acl_arn   # Web ACL ARN
    } : null

    # ──────────────────────────────────────────────────────────────────────
    # Logging - S3 bucket and Firehose configuration
    # ──────────────────────────────────────────────────────────────────────
    logging = var.enable_waf_logging ? {
      bucket_name         = aws_s3_bucket.waf_logs[0].bucket                    # S3 bucket name
      bucket_arn          = aws_s3_bucket.waf_logs[0].arn                       # S3 bucket ARN
      firehose_stream_arn = aws_kinesis_firehose_delivery_stream.waf_logs[0].arn  # Firehose stream ARN
      firehose_stream_name = aws_kinesis_firehose_delivery_stream.waf_logs[0].name # Firehose stream name

      retention = {
        blocked_days = var.blocked_logs_retention_days     # Blocked logs retention
        allowed_days = var.allowed_logs_retention_days     # Allowed logs retention
        error_days   = var.error_logs_retention_days       # Error logs retention
      }

      lambda_router = {
        function_name = aws_lambda_function.waf_log_router[0].function_name  # Lambda function name
        function_arn  = aws_lambda_function.waf_log_router[0].arn            # Lambda function ARN
      }
    } : null

    # ──────────────────────────────────────────────────────────────────────
    # Rule Groups - Enabled managed rule groups
    # ──────────────────────────────────────────────────────────────────────
    rule_groups = {
      # Phase 1: Baseline protection
      core_rule_set       = var.enable_core_rule_set           # OWASP Top 10 (700 WCU)
      known_bad_inputs    = var.enable_known_bad_inputs        # Known malicious patterns (200 WCU)
      sqli_protection     = var.enable_sqli_rule_set           # SQL injection (200 WCU)
      ip_reputation       = var.enable_ip_reputation_list      # Malicious IPs (25 WCU)
      admin_protection    = var.enable_admin_protection        # Admin pages (100 WCU)
      anonymous_ip_list   = var.enable_anonymous_ip_list       # VPN/Proxy blocking (50 WCU)

      # Phase 2: Stack-specific
      wordpress_rules     = var.enable_wordpress_rules         # WordPress (100 WCU)
      php_rules           = var.enable_php_rules               # PHP (100 WCU)
      linux_rules         = var.enable_linux_rules             # Linux OS (200 WCU)
      unix_rules          = var.enable_unix_rules              # POSIX/Unix (100 WCU)
      windows_rules       = var.enable_windows_rules           # Windows OS (200 WCU)

      # Phase 3: Paid/Advanced
      bot_control         = var.enable_bot_control             # Bot Control (50 WCU, PAID)
      atp                 = var.enable_atp                     # Account Takeover Prevention (50 WCU, PAID)
      acfp                = var.enable_acfp                    # Account Creation Fraud Prevention (50 WCU, PAID)
    }

    # ──────────────────────────────────────────────────────────────────────
    # Rate Limiting Configuration
    # ──────────────────────────────────────────────────────────────────────
    rate_limiting = {
      enabled   = var.enable_rate_limiting      # Rate limiting enabled
      threshold = var.rate_limit_threshold      # Requests per IP per 5 min
    }

    # ──────────────────────────────────────────────────────────────────────
    # Rule Exclusions - Specific rules excluded from managed rule groups
    # ──────────────────────────────────────────────────────────────────────
    rule_exclusions = {
      size_restrictions_body = {
        enabled     = var.exclude_size_restrictions_body
        rule_name   = "SizeRestrictions_BODY"
        rule_group  = "CoreRuleSet"
        action      = var.exclude_size_restrictions_body ? "COUNT" : "BLOCK"
        reason      = "Allow file uploads (multipart/form-data)"
      }
      cross_site_scripting_body = {
        enabled     = var.exclude_cross_site_scripting_body
        rule_name   = "CrossSiteScripting_BODY"
        rule_group  = "CoreRuleSet"
        action      = var.exclude_cross_site_scripting_body ? "COUNT" : "BLOCK"
        reason      = "Allow HTML/JavaScript content in request body (rich text editors, code examples)"
      }
      no_user_agent_header = {
        enabled     = var.exclude_no_user_agent_header
        rule_name   = "NoUserAgent_HEADER"
        rule_group  = "CoreRuleSet"
        action      = var.exclude_no_user_agent_header ? "COUNT" : "BLOCK"
        reason      = "Allow requests without User-Agent header (health checks, internal APIs, monitoring tools)"
      }
    }

    # ──────────────────────────────────────────────────────────────────────
    # Path Exclusions - Paths excluded from Core/Admin/SQLi/KnownBadInputs rules
    # Uses scope_down_statement (no additional WCU cost)
    # ──────────────────────────────────────────────────────────────────────
    core_rule_set_path_exclusions = {
      enabled                    = length(var.core_rule_sets_excluded_paths) > 0
      excluded_paths             = var.core_rule_sets_excluded_paths
      count                      = length(var.core_rule_sets_excluded_paths)
      affected_rules             = ["CoreRuleSet"]
      implementation             = "scope_own_statement"
      wcu_cost                   = 0  # Scope-down statements don't add WCU cost
    }

    # ──────────────────────────────────────────────────────────────────────
    # CloudWatch Metrics
    # ──────────────────────────────────────────────────────────────────────
    metrics = {
      metric_name  = "${var.env}-${var.project_id}-waf"           # CloudWatch metric name
      namespace    = "AWS/WAFV2"                                   # Metric namespace
      sampled_requests = true                                      # Sampled requests enabled
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled      = true
      environment         = var.env
      project_id          = var.project_id
      waf_enabled         = true
      logging_enabled     = var.enable_waf_logging
      alb_associated      = var.alb_arn != null

      # Estimated WCU usage (approximate)
      total_wcu_used = (
        (var.enable_core_rule_set ? 700 : 0) +
        (var.enable_known_bad_inputs ? 200 : 0) +
        (var.enable_sqli_rule_set ? 200 : 0) +
        (var.enable_ip_reputation_list ? 25 : 0) +
        (var.enable_admin_protection ? 100 : 0) +
        (var.enable_anonymous_ip_list ? 50 : 0) +
        (var.enable_wordpress_rules ? 100 : 0) +
        (var.enable_php_rules ? 100 : 0) +
        (var.enable_linux_rules ? 200 : 0) +
        (var.enable_unix_rules ? 100 : 0) +
        (var.enable_windows_rules ? 200 : 0) +
        (var.enable_bot_control ? 50 : 0) +
        (var.enable_atp ? 50 : 0) +
        (var.enable_acfp ? 50 : 0)
      )

      wcu_remaining = 1500 - (
        (var.enable_core_rule_set ? 700 : 0) +
        (var.enable_known_bad_inputs ? 200 : 0) +
        (var.enable_sqli_rule_set ? 200 : 0) +
        (var.enable_ip_reputation_list ? 25 : 0) +
        (var.enable_admin_protection ? 100 : 0) +
        (var.enable_anonymous_ip_list ? 50 : 0) +
        (var.enable_wordpress_rules ? 100 : 0) +
        (var.enable_php_rules ? 100 : 0) +
        (var.enable_linux_rules ? 200 : 0) +
        (var.enable_unix_rules ? 100 : 0) +
        (var.enable_windows_rules ? 200 : 0) +
        (var.enable_bot_control ? 50 : 0) +
        (var.enable_atp ? 50 : 0) +
        (var.enable_acfp ? 50 : 0)
      )

      baseline_rules_enabled = (
        (var.enable_core_rule_set ? 1 : 0) +
        (var.enable_known_bad_inputs ? 1 : 0) +
        (var.enable_sqli_rule_set ? 1 : 0) +
        (var.enable_ip_reputation_list ? 1 : 0)
      )

      stack_rules_enabled = (
        (var.enable_wordpress_rules ? 1 : 0) +
        (var.enable_php_rules ? 1 : 0) +
        (var.enable_linux_rules ? 1 : 0) +
        (var.enable_unix_rules ? 1 : 0) +
        (var.enable_windows_rules ? 1 : 0)
      )

      paid_features_enabled = (
        (var.enable_bot_control ? 1 : 0) +
        (var.enable_atp ? 1 : 0) +
        (var.enable_acfp ? 1 : 0)
      )
    }
  } : null
}

