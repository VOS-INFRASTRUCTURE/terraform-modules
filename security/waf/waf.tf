################################################################################
# AWS WAF Web ACL - Variable-Driven Configuration
#
# IMPORTANT:
# - AWS WAF enforces a maximum of 1500 WCU (Web ACL Capacity Units) per Web ACL
# - Rule groups below include their WCU cost in comments
# - ALWAYS recalculate total WCU before enabling additional rules
# - Use outputs to check: module.waf.waf.summary.total_wcu_used
#
# WCU Limit: 1500
# Current baseline (all Phase 1 enabled): ~1325 WCU
# Rate limiting: 0 WCU (doesn't count toward limit!)
#
# DDoS Protection:
# - AWS Shield Standard: FREE and automatic (network/transport layer)
# - Rate limiting (included): 0 WCU (application layer)
# - AWS Shield Advanced: $3,000/month (not included in this module)
################################################################################

resource "aws_wafv2_web_acl" "waf" {
  count = var.enable_waf ? 1 : 0

  name        = "${local.resource_prefix}-${var.project_id}-waf"
  description = "${var.env} AWS WAF protecting ${var.project_id} Application Load Balancer"
  scope       = var.waf_scope

  ##########################################################################
  # Default Action - Allow all traffic unless blocked by rules
  ##########################################################################
  default_action {
    allow {}
  }

  ##########################################################################
  # Visibility / Metrics
  ##########################################################################
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.resource_prefix}-${var.project_id}-waf"
    sampled_requests_enabled   = true
  }

  ##########################################################################
  # PHASE 1 – BASELINE PROTECTION (Variable-Driven)
  #
  # Core security rules recommended for all applications.
  # Total WCU: ~1325 (with all Phase 1 enabled)
  ##########################################################################

  # ------------------------------------------------------------------------
  # Core Rule Set (OWASP Top 10)
  # Capacity: 700 WCU
  # Protects against: XSS, LFI, RCE, SQLi (basic), path traversal
  #
  # Path Exclusions: Applied via scope_down_statement if var.core_rule_sets_excluded_paths
  # is not empty. Excluded paths will NOT be evaluated by this rule group.
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_core_rule_set ? [1] : []

    content {
      name     = "AWSManagedRulesCommonRuleSet"
      priority = 1

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesCommonRuleSet"
          vendor_name = "AWS"

          # Exclude specific rules from this rule group
          # SizeRestrictions_BODY: Blocks large request bodies (file uploads)
          # Enable this exclusion if your application supports file uploads
          dynamic "rule_action_override" {
            for_each = var.exclude_size_restrictions_body ? [1] : []

            content {
              name = "SizeRestrictions_BODY"
              action_to_use {
                count {}
              }
            }
          }

          # CrossSiteScripting_BODY: Blocks potential XSS in request body
          # Enable this exclusion if your application handles HTML/JavaScript content
          # (e.g., rich text editors, code examples, documentation platforms)
          dynamic "rule_action_override" {
            for_each = var.exclude_cross_site_scripting_body ? [1] : []

            content {
              name = "CrossSiteScripting_BODY"
              action_to_use {
                count {}
              }
            }
          }

          # NoUserAgent_HEADER: Blocks requests without User-Agent header
          # Enable this exclusion if you have health checks, internal APIs, or monitoring
          # tools that don't send User-Agent headers (e.g., Kubernetes probes, Lambda)
          dynamic "rule_action_override" {
            for_each = var.exclude_no_user_agent_header ? [1] : []

            content {
              name = "NoUserAgent_HEADER"
              action_to_use {
                count {}
              }
            }
          }

          # Exclude specific paths from this rule group evaluation
          # Scope-down statement: "Evaluate this rule group ONLY if path does NOT match core_rule_sets_excluded_paths"

          # Case 1: Single excluded path - use byte_match_statement directly
          dynamic "scope_down_statement" {
            for_each = length(var.core_rule_sets_excluded_paths) == 1 ? [1] : []

            content {
              not_statement {
                statement {
                  byte_match_statement {
                    search_string         = var.core_rule_sets_excluded_paths[0]
                    positional_constraint = "STARTS_WITH"

                    field_to_match {
                      uri_path {}
                    }

                    text_transformation {
                      priority = 0
                      type     = "NONE"
                    }
                  }
                }
              }
            }
          }

          # Case 2: Multiple excluded paths - use or_statement (requires 2+ statements)
          dynamic "scope_down_statement" {
            for_each = length(var.core_rule_sets_excluded_paths) > 1 ? [1] : []

            content {
              not_statement {
                statement {
                  or_statement {
                    dynamic "statement" {
                      for_each = var.core_rule_sets_excluded_paths

                      content {
                        byte_match_statement {
                          search_string         = statement.value
                          positional_constraint = "STARTS_WITH"

                          field_to_match {
                            uri_path {}
                          }

                          text_transformation {
                            priority = 0
                            type     = "NONE"
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "CommonRuleSet"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Admin Protection
  # Capacity: 100 WCU
  # Protects against: Admin panel attacks, unauthorized access
  # WARNING: Can cause false positives
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_admin_protection ? [1] : []

    content {
      name     = "AWSManagedRulesAdminProtectionRuleSet"
      priority = 2

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAdminProtectionRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AdminProtection"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Known Bad Inputs
  # Capacity: 200 WCU
  # Protects against: Log4Shell, Spring4Shell, known CVEs
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_known_bad_inputs ? [1] : []

    content {
      name     = "AWSManagedRulesKnownBadInputsRuleSet"
      priority = 3

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesKnownBadInputsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "KnownBadInputs"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # SQL Injection Protection
  # Capacity: 200 WCU
  # Protects against: Advanced SQL injection attacks
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_sqli_rule_set ? [1] : []

    content {
      name     = "AWSManagedRulesSQLiRuleSet"
      priority = 4

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesSQLiRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "SQLiRuleSet"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Amazon IP Reputation List
  # Capacity: 25 WCU
  # Protects against: Known malicious IPs, botnets, scanners
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_ip_reputation_list ? [1] : []

    content {
      name     = "AWSManagedRulesAmazonIpReputationList"
      priority = 5

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAmazonIpReputationList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IpReputationList"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Anonymous IP List
  # Capacity: 50 WCU
  # Protects against: VPNs, proxies, Tor exit nodes
  # WARNING: May block legitimate users behind corporate VPNs
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_anonymous_ip_list ? [1] : []

    content {
      name     = "AWSManagedRulesAnonymousIpList"
      priority = 6

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesAnonymousIpList"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AnonymousIpList"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Rate Limiting (Per IP)
  # Capacity: 0 WCU (rate-based rules DON'T count toward WCU limit!)
  #
  # Protects against: DDoS, brute-force, credential stuffing
  # This is your FREE DDoS protection at application layer!
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_rate_limiting ? [1] : []

    content {
      name     = "RateLimitPerIP"
      priority = 7

      action {
        block {}
      }

      statement {
        rate_based_statement {
          limit              = var.rate_limit_threshold
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "RateLimit"
        sampled_requests_enabled   = true
      }
    }
  }

  ##########################################################################
  # PHASE 2 – STACK-SPECIFIC RULES (Variable-Driven)
  #
  # Enable ONLY if your application uses these technologies.
  # Enabling unnecessary rules wastes WCU and may cause false positives.
  #
  # WARNING: Enabling all Phase 2 rules can exceed 1500 WCU limit.
  # Choose selectively based on your application stack.
  ##########################################################################

  # ------------------------------------------------------------------------
  # WordPress Application Rules
  # Capacity: 100 WCU
  # NOTE: Only enable if using WordPress
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_wordpress_rules ? [1] : []

    content {
      name     = "AWSManagedRulesWordPressRuleSet"
      priority = 10

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesWordPressRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "WordPressRules"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # PHP Application Rules
  # Capacity: 100 WCU
  # NOTE: Only enable if using PHP
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_php_rules ? [1] : []

    content {
      name     = "AWSManagedRulesPHPRuleSet"
      priority = 11

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesPHPRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "PHPRules"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Linux Operating System Rules
  # Capacity: 200 WCU
  # NOTE: Generally unnecessary behind ALB. Enable only if OS is exposed.
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_linux_rules ? [1] : []

    content {
      name     = "AWSManagedRulesLinuxRuleSet"
      priority = 12

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesLinuxRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "LinuxOSRules"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # POSIX/Unix Operating System Rules
  # Capacity: 100 WCU
  # NOTE: Only enable if needed based on your OS
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_unix_rules ? [1] : []

    content {
      name     = "AWSManagedRulesUnixRuleSet"
      priority = 13

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesUnixRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "POSIXRules"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Windows Operating System Rules
  # Capacity: 200 WCU
  # NOTE: Only enable if running Windows backend servers
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_windows_rules ? [1] : []

    content {
      name     = "AWSManagedRulesWindowsRuleSet"
      priority = 14

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesWindowsRuleSet"
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "WindowsOSRules"
        sampled_requests_enabled   = true
      }
    }
  }

  ##########################################################################
  # PHASE 3 – PAID / ADVANCED PROTECTION (Variable-Driven)
  #
  # These features incur additional monthly costs + usage fees.
  # Enable only if you have specific security requirements.
  #
  # Pricing:
  # - Bot Control: $10/month + $1 per million requests
  # - ATP: $10/month + $1 per 1,000 login attempts
  # - ACFP: $10/month + $1 per 1,000 account creations
  ##########################################################################

  # ------------------------------------------------------------------------
  # Bot Control (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per million requests
  # Protects against: Bots, scrapers, automated tools
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []

    content {
      name     = "AWSManagedRulesBotControlRuleSet"
      priority = 20

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = var.bot_control_inspection_level
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "BotControl"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Account Takeover Prevention (ATP) (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per 1,000 login attempts
  # Protects against: Credential stuffing, compromised credentials
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_atp ? [1] : []

    content {
      name     = "AWSManagedRulesATPRuleSet"
      priority = 21

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesATPRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_atp_rule_set {
              login_path = var.atp_login_path
              request_inspection {
                payload_type = "JSON"
                username_field {
                  identifier = var.atp_username_field
                }
                password_field {
                  identifier = var.atp_password_field
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AccountTakeoverProtection"
        sampled_requests_enabled   = true
      }
    }
  }

  # ------------------------------------------------------------------------
  # Account Creation Fraud Prevention (ACFP) (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per 1,000 account creations
  # Protects against: Fake accounts, mass registration fraud
  # ------------------------------------------------------------------------
  dynamic "rule" {
    for_each = var.enable_acfp ? [1] : []

    content {
      name     = "AWSManagedRulesACFPRuleSet"
      priority = 22

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesACFPRuleSet"
          vendor_name = "AWS"

          managed_rule_group_configs {
            aws_managed_rules_acfp_rule_set {
              creation_path          = var.acfp_creation_path
              registration_page_path = var.acfp_registration_page_path
              request_inspection {
                payload_type = "JSON"
                username_field {
                  identifier = var.acfp_username_field
                }
                email_field {
                  identifier = var.acfp_email_field
                }
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AccountCreationFraudPrevention"
        sampled_requests_enabled   = true
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-waf"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "WAF"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# Associate Web ACL with Application Load Balancer
#
# Note: Only creates association if ALB ARN is provided and WAF is enabled
################################################################################
resource "aws_wafv2_web_acl_association" "alb_waf_assoc" {
  count = var.enable_waf && var.alb_arn != null ? 1 : 0

  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.waf[0].arn
}
