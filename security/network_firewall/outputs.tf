################################################################################
# Outputs for AWS Network Firewall Module
################################################################################

output "network_firewall" {
  description = "Complete AWS Network Firewall configuration and resources"
  value = {
    # Firewall enabled status
    enabled = var.enable_network_firewall

    # Firewall details
    firewall_id   = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].id : null
    firewall_arn  = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].arn : null
    firewall_name = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].name : null

    # Firewall endpoints (for route table configuration)
    firewall_status = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].firewall_status : null

    # Firewall policy
    policy_arn  = var.enable_network_firewall ? aws_networkfirewall_firewall_policy.main[0].arn : null
    policy_name = var.enable_network_firewall ? aws_networkfirewall_firewall_policy.main[0].name : null

    # Rule groups
    rule_groups = {
      domain_filtering = {
        enabled = var.enable_domain_filtering
        arn     = var.enable_network_firewall && var.enable_domain_filtering ? aws_networkfirewall_rule_group.domain_filtering[0].arn : null
        name    = var.enable_network_firewall && var.enable_domain_filtering ? aws_networkfirewall_rule_group.domain_filtering[0].name : null
      }
      ip_filtering = {
        enabled = var.enable_ip_filtering && length(var.blocked_ip_ranges) > 0
        arn     = var.enable_network_firewall && var.enable_ip_filtering && length(var.blocked_ip_ranges) > 0 ? aws_networkfirewall_rule_group.ip_filtering[0].arn : null
        name    = var.enable_network_firewall && var.enable_ip_filtering && length(var.blocked_ip_ranges) > 0 ? aws_networkfirewall_rule_group.ip_filtering[0].name : null
      }
      protocol_filtering = {
        enabled = var.enable_protocol_filtering && length(var.blocked_protocols) > 0
        arn     = var.enable_network_firewall && var.enable_protocol_filtering && length(var.blocked_protocols) > 0 ? aws_networkfirewall_rule_group.protocol_filtering[0].arn : null
        name    = var.enable_network_firewall && var.enable_protocol_filtering && length(var.blocked_protocols) > 0 ? aws_networkfirewall_rule_group.protocol_filtering[0].name : null
      }
      suricata_ids = {
        enabled = var.enable_suricata_rules
        arn     = var.enable_network_firewall && var.enable_suricata_rules ? aws_networkfirewall_rule_group.suricata_rules[0].arn : null
        name    = var.enable_network_firewall && var.enable_suricata_rules ? aws_networkfirewall_rule_group.suricata_rules[0].name : null
      }
    }

    # Logging configuration
    logging = {
      flow_logs = {
        enabled           = var.enable_flow_logs
        log_group_name    = var.enable_network_firewall && var.enable_flow_logs && var.log_destination_type == "CloudWatchLogs" ? aws_cloudwatch_log_group.firewall_flow_logs[0].name : null
        log_group_arn     = var.enable_network_firewall && var.enable_flow_logs && var.log_destination_type == "CloudWatchLogs" ? aws_cloudwatch_log_group.firewall_flow_logs[0].arn : null
        retention_days    = var.log_retention_days
      }
      alert_logs = {
        enabled           = var.enable_alert_logs
        log_group_name    = var.enable_network_firewall && var.enable_alert_logs && var.log_destination_type == "CloudWatchLogs" ? aws_cloudwatch_log_group.firewall_alert_logs[0].name : null
        log_group_arn     = var.enable_network_firewall && var.enable_alert_logs && var.log_destination_type == "CloudWatchLogs" ? aws_cloudwatch_log_group.firewall_alert_logs[0].arn : null
        retention_days    = var.log_retention_days
      }
    }

    # Protection settings
    protections = {
      firewall_policy_change = var.firewall_policy_change_protection
      subnet_change          = var.subnet_change_protection
      delete_protection      = var.delete_protection
    }
  }
}

output "firewall_endpoint_ids" {
  description = "Firewall status including endpoint IDs (use firewall_status.sync_states for route table configuration)"
  value       = var.enable_network_firewall ? aws_networkfirewall_firewall.main[0].firewall_status : null
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost for AWS Network Firewall"
  value = var.enable_network_firewall ? {
    firewall_endpoints = "~$${length(var.subnet_ids) * 288}/month (${length(var.subnet_ids)} AZ × $288/AZ)"
    data_processing    = "~$0.065/GB processed"
    total_minimum      = "~$${length(var.subnet_ids) * 288}/month + data processing"
    note               = "Actual cost depends on data volume processed"
  } : {
    cost = "$0 (Network Firewall disabled)"
  }
}

