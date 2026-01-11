################################################################################
# CERPAC – AWS WAF Web ACL (Production)
#
# IMPORTANT:
# - AWS WAF enforces a maximum of 1500 WCU (Web ACL Capacity Units) per Web ACL.
# - Rule groups below include their WCU cost in comments.
# - ALWAYS recalculate total WCU before enabling additional rules.
#
# Reference:
#   Total WCU (enabled rules) MUST be ≤ 1500
################################################################################

resource "aws_wafv2_web_acl" "cerpac_waf" {
  name        = "${local.resource_prefix}-cerpac-waf"
  description = "Production AWS WAF protecting the CERPAC Application Load Balancer"
  scope       = "REGIONAL"

  ##########################################################################
  # Default Action
  ##########################################################################
  default_action {
    allow {}
  }

  ##########################################################################
  # Visibility / Metrics
  ##########################################################################
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.resource_prefix}-cerpac-waf"
    sampled_requests_enabled   = true
  }

  ##########################################################################
  # PHASE 1 – BASELINE PROTECTION (ENABLED)
  #
  # Goal:
  # - Strong OWASP-aligned protection
  # - Low false positives
  # - Safe for immediate production use
  #
  # CURRENT PHASE 1 WCU TOTAL = 1325 (within 1500 limit)
  # Previously: 1475 (Admin Protection + Anonymous IP List now disabled)
  ##########################################################################

  # ------------------------------------------------------------------------
  # Core Rule Set (OWASP Top 10)
  # Capacity: 700 WCU
  # ------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  /*
  # ------------------------------------------------------------------------
  # Admin Protection
  # Capacity: 100 WCU
  #
  # Protects against:
  # - Unauthorized access to admin pages
  # - Admin panel exploitation attempts
  # ------------------------------------------------------------------------
  rule {
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
  */

  # ------------------------------------------------------------------------
  # Known Bad Inputs
  # Capacity: 200 WCU
  #
  # Protects against:
  # - Known malicious patterns
  # - OWASP Top 10 vulnerabilities
  # - Log4j, SpringShell, and other CVEs
  # ------------------------------------------------------------------------
  rule {
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

  # ------------------------------------------------------------------------
  # SQL Injection Protection
  # Capacity: 200 WCU
  # ------------------------------------------------------------------------
  rule {
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

  # ------------------------------------------------------------------------
  # Amazon IP Reputation List
  # Capacity: 25 WCU
  #
  # Protects against:
  # - Known malicious IPs based on Amazon threat intelligence
  # - Botnet IPs
  # - Scanning and exploitation sources
  # ------------------------------------------------------------------------
  rule {
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

  /*
  # ------------------------------------------------------------------------
  # Anonymous IP List
  # Capacity: 50 WCU
  #
  # Protects against:
  # - Requests from VPNs, proxies, Tor exit nodes
  # - Anonymization services
  # - Hosting providers used for scraping
  #
  # WARNING:
  # - May block legitimate users behind corporate VPNs
  # - Consider count mode first to assess impact
  # ------------------------------------------------------------------------
  rule {
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
  */

  # ------------------------------------------------------------------------
  # Rate Limiting (Per IP)
  # Capacity: 0 WCU (rate-based rules don't count toward WCU limit)
  #
  # Protects against:
  # - Brute-force attacks
  # - Credential stuffing
  # - Application-layer floods
  # ------------------------------------------------------------------------
  rule {
    name     = "RateLimitPerIP"
    priority = 7

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 1000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  ##########################################################################
  # PHASE 2 – CONDITIONAL / STACK-SPECIFIC RULES (COMMENTED OUT)
  #
  # Enabled ONLY if evidence appears in WAF logs.
  # These rules increase false-positive risk if enabled blindly.
  #
  # WARNING: Enabling all Phase 2 rules will exceed 1500 WCU limit.
  # Choose selectively based on your application stack.
  ##########################################################################

  /*
  # ------------------------------------------------------------------------
  # WordPress Application Rules
  # Capacity: 100 WCU
  #
  # NOTE:
  # - Only enable if WordPress is detected.
  # - Useless and noisy for non-WordPress systems.
  # ------------------------------------------------------------------------
  rule {
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
  */

  /*
  # ------------------------------------------------------------------------
  # PHP Application Rules
  # Capacity: 100 WCU
  #
  # NOTE:
  # - Disabled by default due to false-positive risk.
  # - Enable only with evidence from logs.
  # ------------------------------------------------------------------------
  rule {
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
  */

  /*
  # ------------------------------------------------------------------------
  # Linux Operating System Rules
  # Capacity: 200 WCU
  #
  # NOTE:
  # - Generally unnecessary behind ALB + managed runtime.
  # - Enable only if backend OS is directly exposed.
  # ------------------------------------------------------------------------
  rule {
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
  */

  /*
  # ------------------------------------------------------------------------
  # POSIX Operating System Rules
  # Capacity: 100 WCU
  #
  # NOTE:
  # - Protects against POSIX-specific exploits
  # - Enable only if needed based on your OS
  # ------------------------------------------------------------------------
  rule {
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
  */

  /*
  # ------------------------------------------------------------------------
  # Windows Operating System Rules
  # Capacity: 200 WCU
  #
  # NOTE:
  # - Only enable if running Windows backend servers
  # - Not applicable for Linux-based infrastructure
  # ------------------------------------------------------------------------
  rule {
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
  */

  ##########################################################################
  # PHASE 3 – PAID / HIGH-IMPACT PROTECTION (COMMENTED OUT)
  #
  # These rules incur additional cost and should be enabled deliberately.
  # Pricing: https://aws.amazon.com/waf/pricing/
  ##########################################################################

  /*
  # ------------------------------------------------------------------------
  # Bot Control (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per million requests
  #
  # Protects against:
  # - Automated bots
  # - Scrapers
  # - Search engine crawlers (configurable)
  # - Monitoring/uptime bots
  #
  # RECOMMENDED:
  # - Enable if bot traffic is a concern
  # - Configure bot categories carefully to avoid blocking good bots
  # ------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        # Optional: Configure bot control behavior
        # managed_rule_group_configs {
        #   aws_managed_rules_bot_control_rule_set {
        #     inspection_level = "COMMON"  # or "TARGETED"
        #   }
        # }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BotControl"
      sampled_requests_enabled   = true
    }
  }
  */

  /*
  # ------------------------------------------------------------------------
  # Account Takeover Prevention (ATP) (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per 1,000 login attempts
  #
  # Protects against:
  # - Credential stuffing
  # - Known breached credential patterns
  # - Anomalous login behavior
  #
  # REQUIRED CONFIGURATION:
  # - Must specify login endpoint path
  # - Must configure request inspection (username/password fields)
  #
  # RECOMMENDED:
  # - Enable if login endpoints are exposed
  # ------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesATPRuleSet"
    priority = 21

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesATPRuleSet"
        vendor_name = "AWS"

        # REQUIRED: Configure login path and field inspection
        # managed_rule_group_configs {
        #   aws_managed_rules_atp_rule_set {
        #     login_path = "/login"
        #     request_inspection {
        #       payload_type = "JSON"
        #       username_field {
        #         identifier = "/username"
        #       }
        #       password_field {
        #         identifier = "/password"
        #       }
        #     }
        #   }
        # }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AccountTakeoverProtection"
      sampled_requests_enabled   = true
    }
  }
  */

  /*
  # ------------------------------------------------------------------------
  # Account Creation Fraud Prevention (ACFP) (PAID)
  # Capacity: 50 WCU
  # Cost: $10/month + $1 per 1,000 account creation attempts
  #
  # Protects against:
  # - Fake account creation
  # - Mass account registration
  # - Fraudulent signups
  #
  # REQUIRED CONFIGURATION:
  # - Must specify registration endpoint path
  # - Must configure request inspection fields
  #
  # RECOMMENDED:
  # - Enable if account creation abuse is a concern
  # ------------------------------------------------------------------------
  rule {
    name     = "AWSManagedRulesACFPRuleSet"
    priority = 22

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesACFPRuleSet"
        vendor_name = "AWS"

        # REQUIRED: Configure registration path and field inspection
        # managed_rule_group_configs {
        #   aws_managed_rules_acfp_rule_set {
        #     creation_path = "/signup"
        #     registration_page_path = "/register"
        #     request_inspection {
        #       payload_type = "JSON"
        #       username_field {
        #         identifier = "/username"
        #       }
        #       email_field {
        #         identifier = "/email"
        #       }
        #     }
        #   }
        # }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AccountCreationFraudPrevention"
      sampled_requests_enabled   = true
    }
  }
  */
}

################################################################################
# Associate Web ACL with the CERPAC Application Load Balancer
################################################################################
resource "aws_wafv2_web_acl_association" "cerpac_alb_waf_assoc" {
  resource_arn = aws_lb.cerpac_alb.arn
  web_acl_arn  = aws_wafv2_web_acl.cerpac_waf.arn
}
