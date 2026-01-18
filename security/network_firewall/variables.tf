################################################################################
# Variables for AWS Network Firewall Module
################################################################################

variable "env" {
  description = "Environment name (e.g., staging, production)"
  type        = string
}

variable "project_id" {
  description = "Project identifier for resource naming and tagging"
  type        = string
}

variable "enable_network_firewall" {
  description = "Whether to enable AWS Network Firewall"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where the firewall will be deployed"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "List of subnet IDs for firewall endpoints (one per AZ, should be dedicated firewall subnets)"
  type        = list(string)
  default     = []
}

variable "firewall_policy_change_protection" {
  description = "Enable protection against firewall policy changes"
  type        = bool
  default     = false
}

variable "subnet_change_protection" {
  description = "Enable protection against subnet association changes"
  type        = bool
  default     = false
}

variable "delete_protection" {
  description = "Enable protection against firewall deletion"
  type        = bool
  default     = true
}

################################################################################
# Rule Configuration
################################################################################

variable "enable_stateless_default_actions" {
  description = "Default actions for stateless rules (aws:forward_to_sfe, aws:pass, aws:drop)"
  type        = list(string)
  default     = ["aws:forward_to_sfe"]
}

variable "enable_stateful_default_actions" {
  description = "Default actions for stateful rules (aws:drop_strict, aws:drop_established, aws:alert_strict, aws:alert_established)"
  type        = list(string)
  default     = ["aws:drop_strict", "aws:alert_established"]
}

variable "enable_suricata_rules" {
  description = "Enable Suricata IDS/IPS rules"
  type        = bool
  default     = true
}

variable "enable_domain_filtering" {
  description = "Enable domain filtering (allow/deny specific domains)"
  type        = bool
  default     = true
}

variable "allowed_domains" {
  description = "List of allowed domains for outbound traffic (e.g., ['.amazonaws.com', '.github.com'])"
  type        = list(string)
  default = [
    ".amazonaws.com",
    ".ubuntu.com",
    ".debian.org",
    ".docker.com",
    ".npmjs.org",
    ".github.com",
    ".cloudflare.com"
  ]
}


variable "enable_ip_filtering" {
  description = "Enable IP-based filtering rules"
  type        = bool
  default     = true
}

variable "blocked_ip_ranges" {
  description = "List of blocked IP ranges in CIDR notation"
  type        = list(string)
  default     = []
}

variable "enable_protocol_filtering" {
  description = "Enable protocol-based filtering (block FTP, Telnet, etc.)"
  type        = bool
  default     = true
}

variable "blocked_protocols" {
  description = "List of protocols to block (e.g., ['FTP', 'TELNET', 'SMTP'])"
  type        = list(string)
  default     = ["FTP", "TELNET"]
}

variable "enable_tls_inspection" {
  description = "Enable TLS/SSL traffic inspection (requires certificate)"
  type        = bool
  default     = false
}

variable "tls_inspection_certificate_arn" {
  description = "ARN of ACM certificate for TLS inspection"
  type        = string
  default     = ""
}

################################################################################
# Logging Configuration
################################################################################

variable "enable_flow_logs" {
  description = "Enable firewall flow logs"
  type        = bool
  default     = true
}

variable "enable_alert_logs" {
  description = "Enable firewall alert logs (IDS/IPS alerts)"
  type        = bool
  default     = true
}

variable "log_destination_type" {
  description = "Log destination type: S3, CloudWatchLogs, or KinesisDataFirehose"
  type        = string
  default     = "CloudWatchLogs"

  validation {
    condition     = contains(["S3", "CloudWatchLogs", "KinesisDataFirehose"], var.log_destination_type)
    error_message = "log_destination_type must be S3, CloudWatchLogs, or KinesisDataFirehose"
  }
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group name for firewall logs (if log_destination_type is CloudWatchLogs)"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for firewall logs (if log_destination_type is S3)"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
}

################################################################################
# Advanced Configuration
################################################################################

variable "enable_custom_suricata_rules" {
  description = "Enable custom Suricata rules"
  type        = bool
  default     = false
}

variable "custom_suricata_rules" {
  description = "Custom Suricata rules in Suricata format"
  type        = string
  default     = ""
}

variable "stream_exception_policy" {
  description = "How to handle traffic when unable to evaluate against stateful rules: DROP, CONTINUE, REJECT"
  type        = string
  default     = "DROP"

  validation {
    condition     = contains(["DROP", "CONTINUE", "REJECT"], var.stream_exception_policy)
    error_message = "stream_exception_policy must be DROP, CONTINUE, or REJECT"
  }
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}

