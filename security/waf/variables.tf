################################################################################
# AWS WAF Module Variables
################################################################################

################################################################################
# General Configuration
################################################################################

variable "env" {
  description = "Environment name (e.g., production, staging, development)"
  type        = string

  validation {
    condition     = can(regex("^(production|staging|development|prod|stage|dev)$", var.env))
    error_message = "Environment must be one of: production, staging, development, prod, stage, dev"
  }
}

variable "project_id" {
  description = "Project identifier used in resource naming"
  type        = string
  default     = "cerpac"

  validation {
    condition     = length(var.project_id) > 0 && length(var.project_id) <= 50
    error_message = "Project ID must be between 1 and 50 characters"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

################################################################################
# WAF Configuration
################################################################################

variable "enable_waf" {
  description = "Enable AWS WAF Web ACL"
  type        = bool
  default     = true
}

variable "waf_scope" {
  description = "Scope of the WAF (REGIONAL for ALB/API Gateway, CLOUDFRONT for CloudFront)"
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.waf_scope)
    error_message = "WAF scope must be either REGIONAL or CLOUDFRONT"
  }
}

variable "alb_arn" {
  description = "ARN of the Application Load Balancer to associate with WAF (required if enable_waf = true)"
  type        = string
  default     = null
}

variable "alb_name" {
  description = "Name of the ALB for resource naming (defaults to 'app-alb')"
  type        = string
  default     = null
}

################################################################################
# AWS Managed Rule Groups - Phase 1 (Baseline Protection)
################################################################################

variable "enable_core_rule_set" {
  description = "Enable AWS Managed Core Rule Set (OWASP Top 10) - 700 WCU"
  type        = bool
  default     = true
}

variable "exclude_size_restrictions_body" {
  description = <<-EOT
    Exclude SizeRestrictions_BODY rule from Core Rule Set (changes action to COUNT instead of BLOCK).

    Why exclude this rule:
    - SizeRestrictions_BODY blocks requests with large body sizes (typically >8KB)
    - This is problematic for file uploads (multipart/form-data)
    - Common scenarios: Profile picture uploads, document uploads, image uploads

    When to enable (set to true):
    - Your application supports file uploads
    - You're seeing legitimate uploads being blocked
    - You have other upload size limits in place (application-level, ALB limits)

    Security considerations:
    - When excluded, this rule will COUNT (log only) instead of BLOCK
    - All other Core Rule Set rules still apply (XSS, SQLi, etc.)
    - Ensure your application has upload size limits to prevent abuse
    - ALB has a 1MB payload limit by default (can be increased to 8MB)

    Default: false (rule is active and blocks large bodies)
  EOT
  type        = bool
  default     = false
}

variable "exclude_cross_site_scripting_body" {
  description = <<-EOT
    Exclude CrossSiteScripting_BODY rule from Core Rule Set (changes action to COUNT instead of BLOCK).

    Why exclude this rule:
    - CrossSiteScripting_BODY blocks request bodies containing HTML/JavaScript patterns
    - This is problematic for legitimate use cases with HTML content
    - Common scenarios:
      * Rich text editors (TinyMCE, CKEditor, Quill)
      * Code snippet sharing platforms
      * Documentation with code examples
      * HTML email composition
      * Markdown editors with HTML preview

    When to enable (set to true):
    - Your application has rich text editing functionality
    - Users can submit HTML/JavaScript content legitimately
    - You're seeing legitimate content being blocked (e.g., <script> in code examples)
    - You have server-side XSS sanitization in place

    Security considerations:
    - When excluded, this rule will COUNT (log only) instead of BLOCK
    - ⚠️ CRITICAL: Implement server-side XSS sanitization/escaping
    - ⚠️ CRITICAL: Never render user HTML without sanitization
    - Use libraries like DOMPurify, bleach, or html-sanitizer
    - All other Core Rule Set rules still apply (SQLi, path traversal, etc.)
    - CrossSiteScripting_QUERYARGUMENTS still blocks XSS in URL parameters

    Example sanitization (Node.js):
      const DOMPurify = require('isomorphic-dompurify');
      const cleanHtml = DOMPurify.sanitize(userInput);

    Default: false (rule is active and blocks XSS patterns in body)
  EOT
  type        = bool
  default     = false
}

variable "exclude_no_user_agent_header" {
  description = <<-EOT
    Exclude NoUserAgent_HEADER rule from Core Rule Set (changes action to COUNT instead of BLOCK).

    Why exclude this rule:
    - NoUserAgent_HEADER blocks requests without a User-Agent header
    - This is commonly used to block basic bots and scrapers
    - However, legitimate use cases exist without User-Agent headers

    Common scenarios requiring exclusion:
    - Monitoring/health check tools (Kubernetes liveness/readiness probes)
    - Internal API calls from microservices
    - Serverless functions (Lambda, Cloud Functions)
    - IoT devices with minimal HTTP clients
    - Mobile apps with custom HTTP implementations
    - Automation scripts and scheduled jobs
    - Load balancer health checks (ALB, NLB)

    When to enable (set to true):
    - You have health check endpoints that don't send User-Agent
    - Internal services communicate without User-Agent headers
    - You're seeing legitimate requests being blocked
    - Your monitoring system doesn't set User-Agent

    Security considerations:
    - When excluded, this rule will COUNT (log only) instead of BLOCK
    - ⚠️ Missing User-Agent is a common bot indicator
    - Consider implementing custom rate limiting for no-User-Agent requests
    - Monitor CloudWatch metrics for NoUserAgent_HEADER counts
    - Alternative: Add User-Agent to your health checks/internal tools
    - All other Core Rule Set rules still apply

    Best practice alternatives:
    1. Exclude specific paths instead (e.g., /health, /ready) using core_rule_sets_excluded_paths
    2. Add User-Agent header to your tools/scripts
    3. Use scope-down statement to allow no-User-Agent only from specific IPs

    Default: false (rule is active and blocks requests without User-Agent)
  EOT
  type        = bool
  default     = false
}

variable "enable_known_bad_inputs" {
  description = "Enable AWS Managed Known Bad Inputs Rule Set - 200 WCU"
  type        = bool
  default     = true
}

variable "enable_sqli_rule_set" {
  description = "Enable AWS Managed SQL Injection Rule Set - 200 WCU"
  type        = bool
  default     = true
}

variable "enable_ip_reputation_list" {
  description = "Enable AWS Managed IP Reputation List - 25 WCU"
  type        = bool
  default     = true
}

variable "enable_admin_protection" {
  description = "Enable AWS Managed Admin Protection Rule Set - 100 WCU"
  type        = bool
  default     = false  # Optional, can cause false positives
}

variable "enable_anonymous_ip_list" {
  description = "Enable AWS Managed Anonymous IP List (blocks VPNs, proxies, Tor) - 50 WCU"
  type        = bool
  default     = false  # May block legitimate users
}

################################################################################
# Path Exclusions (Scope-Down Statements)
################################################################################

variable "core_rule_sets_excluded_paths" {
  description = <<-EOT
    List of URI paths to exclude from Core Rule Set, Admin Protection, Known Bad Inputs, and SQLi rules.
    Uses scope_down_statement to exclude paths from specific rule groups (not all rules).

    Example: ["/log-viewer", "/admin/debug", "/internal/metrics"]

    How it works:
    - Excluded paths are NOT evaluated by Core Rule Set, Admin Protection, Known Bad Inputs, and SQLi rules
    - Other rules (Rate Limiting, IP Reputation) still apply to excluded paths
    - No additional WCU cost (uses scope_down_statement, not a separate rule)

    Security considerations:
    - Excluded paths still have protection from: Rate limiting, IP reputation, Bot Control (if enabled)
    - Excluded paths bypass: OWASP protection, SQL injection detection, known CVE patterns, admin protection
    - Only exclude internal/admin paths that are secured by other means (authentication, IP restrictions)
    - Review excluded paths regularly

    Common use cases:
    - /log-viewer - Query parameters that look like SQL injection
    - /admin/debug - Paths that trigger path traversal rules
    - /internal/metrics - Special characters in monitoring endpoints
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for path in var.core_rule_sets_excluded_paths : can(regex("^/", path))])
    error_message = "All excluded paths must start with '/'"
  }
}

################################################################################
# Rate Limiting
################################################################################

variable "enable_rate_limiting" {
  description = "Enable rate limiting per IP address"
  type        = bool
  default     = true
}

variable "rate_limit_threshold" {
  description = "Maximum requests per IP per 5 minutes (default: 1000)"
  type        = number
  default     = 1000

  validation {
    condition     = var.rate_limit_threshold >= 100 && var.rate_limit_threshold <= 20000000
    error_message = "Rate limit must be between 100 and 20,000,000 requests per 5 minutes"
  }
}

################################################################################
# AWS Managed Rule Groups - Phase 2 (Stack-Specific)
################################################################################

variable "enable_wordpress_rules" {
  description = "Enable AWS Managed WordPress Rule Set - 100 WCU (only if using WordPress)"
  type        = bool
  default     = false
}

variable "enable_php_rules" {
  description = "Enable AWS Managed PHP Rule Set - 100 WCU (only if using PHP)"
  type        = bool
  default     = false
}

variable "enable_linux_rules" {
  description = "Enable AWS Managed Linux OS Rule Set - 200 WCU (only if Linux backend)"
  type        = bool
  default     = false
}

variable "enable_unix_rules" {
  description = "Enable AWS Managed POSIX/Unix Rule Set - 100 WCU"
  type        = bool
  default     = false
}

variable "enable_windows_rules" {
  description = "Enable AWS Managed Windows OS Rule Set - 200 WCU (only if Windows backend)"
  type        = bool
  default     = false
}

################################################################################
# AWS Managed Rule Groups - Phase 3 (Paid/Advanced)
################################################################################

variable "enable_bot_control" {
  description = "Enable AWS Managed Bot Control (PAID: $10/month + $1 per million requests) - 50 WCU"
  type        = bool
  default     = false
}

variable "bot_control_inspection_level" {
  description = "Bot Control inspection level (COMMON or TARGETED)"
  type        = string
  default     = "COMMON"  # COMMON inspects common bot traffic, TARGETED inspects all traffic for bots (higher cost)

  validation {
    condition     = contains(["COMMON", "TARGETED"], var.bot_control_inspection_level)
    error_message = "Bot control inspection level must be COMMON or TARGETED"
  }
}

variable "enable_atp" {
  description = "Enable Account Takeover Prevention (PAID: $10/month + $1 per 1,000 login attempts) - 50 WCU"
  type        = bool
  default     = false
}

variable "atp_login_path" {
  description = "Login endpoint path for ATP (required if enable_atp = true)"
  type        = string
  default     = "/login"
}

variable "atp_username_field" {
  description = "JSON path to username field for ATP (e.g., /username)"
  type        = string
  default     = "/username"
}

variable "atp_password_field" {
  description = "JSON path to password field for ATP (e.g., /password)"
  type        = string
  default     = "/password"
}

variable "enable_acfp" {
  description = "Enable Account Creation Fraud Prevention (PAID: $10/month + $1 per 1,000 signups) - 50 WCU"
  type        = bool
  default     = false
}

variable "acfp_creation_path" {
  description = "Account creation endpoint path for ACFP (required if enable_acfp = true)"
  type        = string
  default     = "/signup"
}

variable "acfp_registration_page_path" {
  description = "Registration page path for ACFP"
  type        = string
  default     = "/register"
}

variable "acfp_username_field" {
  description = "JSON path to username field for ACFP"
  type        = string
  default     = "/username"
}

variable "acfp_email_field" {
  description = "JSON path to email field for ACFP"
  type        = string
  default     = "/email"
}

################################################################################
# WAF Logging Configuration
################################################################################

variable "enable_waf_logging" {
  description = "Enable WAF logging to S3 via Kinesis Firehose"
  type        = bool
  default     = true
}

variable "blocked_logs_retention_days" {
  description = "Retention period for blocked request logs in days"
  type        = number
  default     = 90

  validation {
    condition     = var.blocked_logs_retention_days >= 1
    error_message = "Blocked logs retention must be at least 1 day"
  }
}

variable "allowed_logs_retention_days" {
  description = "Retention period for allowed request logs in days"
  type        = number
  default     = 7

  validation {
    condition     = var.allowed_logs_retention_days >= 1
    error_message = "Allowed logs retention must be at least 1 day"
  }
}

variable "error_logs_retention_days" {
  description = "Retention period for error logs in days"
  type        = number
  default     = 7

  validation {
    condition     = var.error_logs_retention_days >= 1
    error_message = "Error logs retention must be at least 1 day"
  }
}

variable "force_destroy_log_bucket" {
  description = "Allow deletion of S3 log bucket even if it contains objects (DANGEROUS - use only in dev/test)"
  type        = bool
  default     = false
}

################################################################################
# Kinesis Firehose Configuration
################################################################################

variable "firehose_buffering_size" {
  description = "Firehose buffer size in MB (minimum: 64 when using dynamic partitioning)"
  type        = number
  default     = 64

  validation {
    condition     = var.firehose_buffering_size >= 64 && var.firehose_buffering_size <= 128
    error_message = "Firehose buffering size must be between 64 and 128 MB"
  }
}

variable "firehose_buffering_interval" {
  description = "Firehose buffer interval in seconds"
  type        = number
  default     = 60

  validation {
    condition     = var.firehose_buffering_interval >= 60 && var.firehose_buffering_interval <= 900
    error_message = "Firehose buffering interval must be between 60 and 900 seconds"
  }
}

variable "enable_firehose_compression" {
  description = "Enable GZIP compression for Firehose delivery"
  type        = bool
  default     = true
}

