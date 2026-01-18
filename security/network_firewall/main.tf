################################################################################
# AWS Network Firewall Module
#
# Purpose: Deploy AWS Network Firewall for VPC perimeter protection with
#          stateful inspection, IDS/IPS, and domain filtering.
#
# Use Cases:
# - Multi-protocol traffic inspection (not just HTTP/HTTPS)
# - Outbound domain filtering (allow/block specific domains)
# - IDS/IPS using Suricata rules
# - Protocol-based filtering (block FTP, Telnet, etc.)
# - Deep packet inspection
#
# Cost: ~$350-500/month (expensive - only use if needed)
# - Firewall endpoint: ~$0.395/hour = ~$288/month per AZ
# - Data processing: $0.065/GB
#
# ⚠️ WARNING: This is expensive! Only enable if you have specific requirements
#             that WAF + Security Groups cannot handle.
#
# Prerequisites:
# - Dedicated subnets for firewall endpoints (one per AZ)
# - Route tables configured to route traffic through firewall
# - VPC with multiple availability zones
################################################################################


################################################################################
# CloudWatch Log Groups (if using CloudWatch for logs)
################################################################################

resource "aws_cloudwatch_log_group" "firewall_flow_logs" {
  count = var.enable_network_firewall && var.enable_flow_logs && var.log_destination_type == "CloudWatchLogs" ? 1 : 0

  name              = var.cloudwatch_log_group_name != "" ? var.cloudwatch_log_group_name : "/aws/networkfirewall/${var.env}-${var.project_id}/flow"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-network-firewall-flow-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-FlowLogs"
    },
    var.tags
  )
}

resource "aws_cloudwatch_log_group" "firewall_alert_logs" {
  count = var.enable_network_firewall && var.enable_alert_logs && var.log_destination_type == "CloudWatchLogs" ? 1 : 0

  name              = var.cloudwatch_log_group_name != "" ? "${var.cloudwatch_log_group_name}-alerts" : "/aws/networkfirewall/${var.env}-${var.project_id}/alert"
  retention_in_days = var.log_retention_days

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-network-firewall-alert-logs"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-AlertLogs"
    },
    var.tags
  )
}

################################################################################
# Stateful Rule Group - Domain Filtering
#
# Purpose: Allow/block specific domains for outbound traffic.
# Example: Block access to malware C2 servers, allow only approved APIs.
################################################################################

resource "aws_networkfirewall_rule_group" "domain_filtering" {
  count = var.enable_network_firewall && var.enable_domain_filtering ? 1 : 0

  name        = "${var.env}-${var.project_id}-domain-filter"
  type        = "STATEFUL"
  capacity    = 100
  description = "Domain filtering for outbound traffic"

  rule_group {
    rules_source {
      rules_source_list {
        generated_rules_type = "ALLOWLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = var.allowed_domains
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-domain-filter"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-DomainFilter"
    },
    var.tags
  )
}

################################################################################
# Stateful Rule Group - IP Filtering
#
# Purpose: Block traffic to/from specific IP addresses or ranges.
# Example: Block known malicious IPs, C2 servers.
################################################################################

resource "aws_networkfirewall_rule_group" "ip_filtering" {
  count = var.enable_network_firewall && var.enable_ip_filtering && length(var.blocked_ip_ranges) > 0 ? 1 : 0

  name        = "${var.env}-${var.project_id}-ip-filter"
  type        = "STATEFUL"
  capacity    = 100
  description = "Block traffic to malicious IP ranges"

  rule_group {
    rules_source {
      stateful_rule {
        action = "DROP"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "IP"
          source           = join(",", var.blocked_ip_ranges)
          source_port      = "ANY"
        }

        rule_option {
          keyword = "sid:1"
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-ip-filter"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-IPFilter"
    },
    var.tags
  )
}

################################################################################
# Stateful Rule Group - Protocol Filtering
#
# Purpose: Block insecure protocols (FTP, Telnet, SMTP, etc.)
# Example: Prevent use of unencrypted protocols.
################################################################################

resource "aws_networkfirewall_rule_group" "protocol_filtering" {
  count = var.enable_network_firewall && var.enable_protocol_filtering && length(var.blocked_protocols) > 0 ? 1 : 0

  name        = "${var.env}-${var.project_id}-protocol-filter"
  type        = "STATEFUL"
  capacity    = 50
  description = "Block insecure protocols"

  rule_group {
    rules_source {
      # Block FTP (ports 20-21)
      dynamic "stateful_rule" {
        for_each = contains(var.blocked_protocols, "FTP") ? [1] : []
        content {
          action = "DROP"
          header {
            destination      = "ANY"
            destination_port = "20:21"
            direction        = "ANY"
            protocol         = "TCP"
            source           = "ANY"
            source_port      = "ANY"
          }
          rule_option {
            keyword = "sid:100"
          }
        }
      }

      # Block Telnet (port 23)
      dynamic "stateful_rule" {
        for_each = contains(var.blocked_protocols, "TELNET") ? [1] : []
        content {
          action = "DROP"
          header {
            destination      = "ANY"
            destination_port = "23"
            direction        = "ANY"
            protocol         = "TCP"
            source           = "ANY"
            source_port      = "ANY"
          }
          rule_option {
            keyword = "sid:101"
          }
        }
      }

      # Block SMTP (port 25) - if specified
      dynamic "stateful_rule" {
        for_each = contains(var.blocked_protocols, "SMTP") ? [1] : []
        content {
          action = "DROP"
          header {
            destination      = "ANY"
            destination_port = "25"
            direction        = "ANY"
            protocol         = "TCP"
            source           = "ANY"
            source_port      = "ANY"
          }
          rule_option {
            keyword = "sid:102"
          }
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-protocol-filter"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-ProtocolFilter"
    },
    var.tags
  )
}

################################################################################
# Stateful Rule Group - Suricata IDS/IPS Rules
#
# Purpose: Use Suricata rules for intrusion detection/prevention.
# Example: Detect SQL injection, XSS, exploit attempts in network traffic.
################################################################################

resource "aws_networkfirewall_rule_group" "suricata_rules" {
  count = var.enable_network_firewall && var.enable_suricata_rules ? 1 : 0

  name        = "${var.env}-${var.project_id}-suricata-ids"
  type        = "STATEFUL"
  capacity    = 1000
  description = "Suricata IDS/IPS rules for threat detection"

  rule_group {
    rules_source {
      rules_string = var.enable_custom_suricata_rules && var.custom_suricata_rules != "" ? var.custom_suricata_rules : <<-EOT
        # Basic Suricata rules for common threats
        # Alert on SQL injection attempts
        alert http any any -> any any (msg:"Possible SQL Injection"; flow:established,to_server; content:"SELECT"; http_uri; content:"FROM"; distance:0; http_uri; sid:1000001; rev:1;)

        # Alert on XSS attempts
        alert http any any -> any any (msg:"Possible XSS Attack"; flow:established,to_server; content:"<script"; http_uri; sid:1000002; rev:1;)

        # Alert on command injection
        alert http any any -> any any (msg:"Possible Command Injection"; flow:established,to_server; content:"|3B|"; http_uri; content:"bash"; distance:0; http_uri; sid:1000003; rev:1;)

        # Alert on directory traversal
        alert http any any -> any any (msg:"Possible Directory Traversal"; flow:established,to_server; content:"../"; http_uri; sid:1000004; rev:1;)

        # Drop known malware signatures
        drop ip any any -> any any (msg:"Known Malware Signature"; content:"|E8 00 00 00 00|"; sid:1000005; rev:1;)
      EOT
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-suricata-ids"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-IDS-IPS"
    },
    var.tags
  )
}

################################################################################
# Firewall Policy
#
# Purpose: Combines all rule groups and defines default actions.
################################################################################

resource "aws_networkfirewall_firewall_policy" "main" {
  count = var.enable_network_firewall ? 1 : 0

  name        = "${var.env}-${var.project_id}-firewall-policy"
  description = "Network Firewall policy with stateful/stateless rules"

  firewall_policy {
    # Stateless rule default actions
    stateless_default_actions          = var.enable_stateless_default_actions
    stateless_fragment_default_actions = var.enable_stateless_default_actions

    # Stateful rule groups
    dynamic "stateful_rule_group_reference" {
      for_each = var.enable_domain_filtering ? [1] : []
      content {
        resource_arn = aws_networkfirewall_rule_group.domain_filtering[0].arn
        priority     = 1
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = var.enable_ip_filtering && length(var.blocked_ip_ranges) > 0 ? [1] : []
      content {
        resource_arn = aws_networkfirewall_rule_group.ip_filtering[0].arn
        priority     = 2
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = var.enable_protocol_filtering && length(var.blocked_protocols) > 0 ? [1] : []
      content {
        resource_arn = aws_networkfirewall_rule_group.protocol_filtering[0].arn
        priority     = 3
      }
    }

    dynamic "stateful_rule_group_reference" {
      for_each = var.enable_suricata_rules ? [1] : []
      content {
        resource_arn = aws_networkfirewall_rule_group.suricata_rules[0].arn
        priority     = 10
      }
    }

    # Stateful engine options
    stateful_engine_options {
      rule_order                  = "STRICT_ORDER"
      stream_exception_policy     = var.stream_exception_policy
    }

    # Stateful default actions
    stateful_default_actions = var.enable_stateful_default_actions

    # TLS inspection configuration (optional)
    dynamic "tls_inspection_configuration_arn" {
      for_each = var.enable_tls_inspection && var.tls_inspection_certificate_arn != "" ? [1] : []
      content {
        tls_inspection_configuration_arn = var.tls_inspection_certificate_arn
      }
    }
  }

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-firewall-policy"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall-Policy"
    },
    var.tags
  )
}

################################################################################
# Network Firewall
#
# Purpose: Deploy firewall endpoints in VPC subnets.
################################################################################

resource "aws_networkfirewall_firewall" "main" {
  count = var.enable_network_firewall ? 1 : 0

  name                = "${var.env}-${var.project_id}-network-firewall"
  description         = "Network Firewall for VPC perimeter protection"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.main[0].arn
  vpc_id              = var.vpc_id

  # Deploy firewall endpoints in specified subnets (one per AZ)
  dynamic "subnet_mapping" {
    for_each = var.subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  # Protection settings
  firewall_policy_change_protection = var.firewall_policy_change_protection
  subnet_change_protection          = var.subnet_change_protection
  delete_protection                 = var.delete_protection

  tags = merge(
    {
      Name        = "${var.env}-${var.project_id}-network-firewall"
      Environment = var.env
      Project     = var.project_id
      ManagedBy   = "Terraform"
      Purpose     = "NetworkFirewall"
      CostCenter  = "Security"
    },
    var.tags
  )
}

################################################################################
# Firewall Logging Configuration
#
# Purpose: Send firewall logs to CloudWatch, S3, or Kinesis.
################################################################################

resource "aws_networkfirewall_logging_configuration" "main" {
  count = var.enable_network_firewall && (var.enable_flow_logs || var.enable_alert_logs) ? 1 : 0

  firewall_arn = aws_networkfirewall_firewall.main[0].arn

  logging_configuration {
    # Flow logs
    dynamic "log_destination_config" {
      for_each = var.enable_flow_logs ? [1] : []
      content {
        log_type = "FLOW"
        log_destination_type = var.log_destination_type

        log_destination = var.log_destination_type == "CloudWatchLogs" ? {
          logGroup = aws_cloudwatch_log_group.firewall_flow_logs[0].name
        } : var.log_destination_type == "S3" ? {
          bucketName = var.s3_bucket_name
          prefix     = "network-firewall/flow/"
        } : {}
      }
    }

    # Alert logs (IDS/IPS alerts)
    dynamic "log_destination_config" {
      for_each = var.enable_alert_logs ? [1] : []
      content {
        log_type = "ALERT"
        log_destination_type = var.log_destination_type

        log_destination = var.log_destination_type == "CloudWatchLogs" ? {
          logGroup = aws_cloudwatch_log_group.firewall_alert_logs[0].name
        } : var.log_destination_type == "S3" ? {
          bucketName = var.s3_bucket_name
          prefix     = "network-firewall/alert/"
        } : {}
      }
    }
  }
}

