################################################################################
# Amazon GuardDuty - Intelligent Threat Detection
#
# Purpose: Enable GuardDuty for continuous security monitoring and threat
#          detection using machine learning and threat intelligence.
#
# Features:
# - Base detector for foundational threat detection
# - S3 Protection (malware detection and suspicious access patterns)
# - EKS Protection (Kubernetes audit log analysis)
# - RDS Protection (database activity monitoring)
# - Lambda Protection (serverless function threat detection)
# - Malware Protection (EBS volume scanning)
#
# Threat Detection Sources:
# - VPC Flow Logs (network traffic analysis)
# - CloudTrail Events (API call monitoring)
# - DNS Logs (domain query analysis)
# - S3 Data Events (object-level activity)
# - EKS Audit Logs (Kubernetes API calls)
# - RDS Login Activity (database authentication)
# - Lambda Network Activity (function execution analysis)
#
# Cost Impact:
# - CloudTrail analysis: ~$4.40/million events
# - VPC Flow Logs analysis: ~$1.18/GB
# - DNS Logs analysis: ~$0.40/million queries
# - S3 Protection: ~$0.20/GB analyzed
# - EKS Protection: ~$0.012/GB audit logs
# - Typical production: $50-200/month
################################################################################

################################################################################
# Amazon GuardDuty Detector
#
# Purpose: Core threat detection service that analyzes CloudTrail events,
#          VPC Flow Logs, and DNS logs for malicious activity.
#
# Finding Publishing Frequency:
# - FIFTEEN_MINUTES: Real-time alerting (recommended for production)
# - SIX_HOURS: Batch processing (cost-effective for dev/test)
#
# What it detects:
# - Cryptocurrency mining
# - Unauthorized access attempts
# - Compromised instances communicating with known malicious IPs
# - Unusual API calls or IAM activity
# - Data exfiltration attempts
################################################################################

resource "aws_guardduty_detector" "this" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  # How often findings are published to CloudWatch Events
  # FIFTEEN_MINUTES | SIX_HOURS | ONE_HOUR
  finding_publishing_frequency = var.finding_publishing_frequency

  # Note: Data sources (S3, EKS, RDS, Lambda, EBS Malware) are enabled
  #       via separate aws_guardduty_detector_feature resources below.
  #       The old datasources {} block is deprecated.

  tags = merge(
    var.tags,
    {
      Name        = "${var.env}-${var.project_id}-guardduty"
      Environment = var.env
      Project     = var.project_id
      Purpose     = "ThreatDetection"
      ManagedBy   = "Terraform"
    }
  )
}

################################################################################
# GuardDuty Detector Features (Advanced Protection)
#
# Note: These features require GuardDuty to be enabled first.
#       They provide additional threat detection capabilities beyond the base detector.
################################################################################

# ──────────────────────────────────────────────────────────────────────────────
# S3 Data Events Protection
#
# AWS Console: Protection Plans → S3 Protection
#
# Purpose: Monitor S3 object-level API calls for suspicious activity
#
# Detects:
# - Data exfiltration (unusual download patterns)
# - Malware uploads
# - Ransomware activity
# - Suspicious S3 access patterns
#
# Cost: ~$0.20 per GB of S3 data analyzed
#
# Note: This resource is ALWAYS created when GuardDuty is enabled.
#       We explicitly set status to ENABLED or DISABLED based on variable.
#       This ensures proper cleanup when disabling features.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "s3_data_events" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "S3_DATA_EVENTS"
  status      = var.enable_s3_data_events ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# EKS Audit Logs Protection
#
# AWS Console: Protection Plans → EKS Protection
#
# Purpose: Analyze Kubernetes API audit logs for suspicious activity
#
# Detects:
# - Anonymous access to Kubernetes API
# - Privilege escalation attempts
# - Suspicious container behavior
# - Kubernetes API abuse
#
# Cost: ~$0.012 per GB of audit logs analyzed
#
# Note: This resource is ALWAYS created when GuardDuty is enabled.
#       We explicitly set status to ENABLED or DISABLED based on variable.
#       This ensures proper cleanup when disabling features.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = var.enable_eks_audit_logs ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS Login Activity Protection
#
# AWS Console: Protection Plans → RDS Protection
#
# Purpose: Monitor database login attempts for suspicious activity
#
# Detects:
# - Brute force attacks
# - Login from suspicious IPs
# - Unusual database access patterns
# - Compromised database credentials
#
# Supported: Aurora (MySQL/PostgreSQL), RDS MySQL, RDS PostgreSQL
# Cost: Included in base GuardDuty pricing
#
# Note: This resource is ALWAYS created when GuardDuty is enabled.
#       We explicitly set status to ENABLED or DISABLED based on variable.
#       This ensures proper cleanup when disabling features.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "rds_login_events" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "RDS_LOGIN_EVENTS"
  status      = var.enable_rds_protection ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda Network Activity Protection
#
# AWS Console: Protection Plans → Lambda Protection
#
# Purpose: Monitor Lambda function network activity for threats
#
# Detects:
# - Functions communicating with malicious IPs
# - Data exfiltration via Lambda
# - Compromised Lambda functions
# - Unusual outbound connections
#
# Cost: Included in base GuardDuty pricing
#
# Note: This resource is ALWAYS created when GuardDuty is enabled.
#       We explicitly set status to ENABLED or DISABLED based on variable.
#       This ensures proper cleanup when disabling features.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "lambda_network_logs" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = var.enable_lambda_protection ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# EBS Malware Protection
#
# AWS Console: Protection Plans → Malware Protection → EC2
#
# Purpose: Scan EBS volumes for malware when GuardDuty detects suspicious activity
#
# How it works:
# 1. GuardDuty detects suspicious EC2 instance behavior
# 2. Automatically creates EBS volume snapshot
# 3. Scans snapshot for malware
# 4. Publishes findings with malware details
#
# Cost: $0.10 per GB scanned (only when triggered)
#
# Note: This resource is ALWAYS created when GuardDuty is enabled.
#       We explicitly set status to ENABLED or DISABLED based on variable.
#       This ensures proper cleanup when disabling features.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EBS_MALWARE_PROTECTION"
  status      = var.enable_ebs_malware_protection ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Note: S3 Malware Protection
#
# AWS Console: Protection Plans → Malware Protection → S3
#
# S3 Malware Scanning is NOT available as a GuardDuty detector feature that can
# be enabled via Terraform's aws_guardduty_detector_feature resource.
#
# According to AWS API, valid detector features are:
# - S3_DATA_EVENTS
# - EKS_AUDIT_LOGS
# - EBS_MALWARE_PROTECTION
# - RDS_LOGIN_EVENTS
# - EKS_RUNTIME_MONITORING
# - LAMBDA_NETWORK_LOGS
# - RUNTIME_MONITORING
#
# S3 Malware Scanning must be configured separately:
# 1. Via AWS Console: GuardDuty → Malware Protection → S3
# 2. Or using a different Terraform resource (not aws_guardduty_detector_feature)
#
# This is a limitation of the current Terraform AWS provider.
# The variable enable_s3_malware_protection is kept for future compatibility
# but currently has no effect.
# ──────────────────────────────────────────────────────────────────────────────


# ──────────────────────────────────────────────────────────────────────────────
# Runtime Monitoring (EKS and ECS Fargate)
#
# AWS Console: Protection Plans → Runtime Monitoring
#
# Purpose: Monitor runtime behavior of containerized workloads
#
# How it works:
# 1. Deploys lightweight agent to EKS/ECS Fargate
# 2. Monitors process executions, file access, network connections
# 3. Detects runtime threats in real-time
# 4. Publishes findings for suspicious behavior
#
# What it detects:
# - Privilege escalation attempts
# - Suspicious process executions
# - Unauthorized file access
# - Reverse shells
# - Crypto mining in containers
#
# Supported Platforms:
# - ✅ Amazon EKS (Elastic Kubernetes Service)
# - ✅ Amazon ECS Fargate (serverless containers)
# - ❌ Amazon ECS EC2 launch type (NOT SUPPORTED)
#
# Cost: Varies by vCPU-hours monitored
#
# Important Notes:
# - Only enable if you have EKS clusters or ECS Fargate tasks
# - For ECS EC2 launch type, Runtime Monitoring is NOT available
# - For ECS EC2 instances, use EBS_MALWARE_PROTECTION instead to scan volumes
# - Runtime Monitoring analyzes RUNTIME behavior (processes, files, network)
# - EBS Malware Protection scans DISK contents for malware files
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "runtime_monitoring" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "RUNTIME_MONITORING"
  status      = var.enable_runtime_monitoring ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Runtime Monitoring - EKS Automated Agent Configuration
#
# AWS Console: Protection Plans → Runtime Monitoring → Automated agent configuration → Amazon EKS
#
# Purpose: Automatically deploy and manage GuardDuty security agent on EKS clusters
#
# Requirements:
# - enable_runtime_monitoring = true (base feature must be enabled first)
# - enable_eks_runtime_agent = true (this variable)
#
# When enabled:
# - GuardDuty automatically deploys agent to EKS clusters
# - Handles agent updates and lifecycle automatically
# - No manual kubectl commands required
# - Shows "Automated agent configuration for Amazon EKS is enabled" in console
#
# When disabled:
# - You must manually deploy the GuardDuty agent via kubectl
# - More control but requires manual maintenance
# - Shows "Automated agent configuration for Amazon EKS is not enabled" in console
#
# Note: This is the ONLY runtime monitoring agent that can be automated via Terraform.
#       ECS Fargate and EC2 agents require manual configuration in AWS Console.
#
# Recommendation: Enable if you have EKS clusters
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "eks_runtime_monitoring" {
  count = var.enable_guardduty && var.enable_runtime_monitoring && var.enable_eks_runtime_agent ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_RUNTIME_MONITORING"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ecs_runtime_fargate_monitoring" {
  count = var.enable_guardduty && var.enable_runtime_monitoring && var.enable_ecs_fargate_runtime_agent ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "ECS_FARGATE_AGENT_MANAGEMENT"
  status      = "ENABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Note: ECS Fargate and EC2 Runtime Monitoring Agents
#
# AWS Console: Protection Plans → Runtime Monitoring → Automated agent configuration
#
# ⚠️ IMPORTANT: ECS Fargate and EC2 agents CANNOT be configured via Terraform
#
# After enabling enable_runtime_monitoring = true, you MUST manually configure:
#
# 1. ECS Fargate Agent (if you have ECS Fargate tasks):
#    - Go to: GuardDuty → Runtime Monitoring → Configuration
#    - Find: "Automated agent configuration" section
#    - Click: Enable button for "AWS Fargate (ECS only)"
#    - Result: Agent will be auto-injected into Fargate tasks
#
# 2. EC2 Agent (if you have standalone EC2 instances):
#    - Go to: GuardDuty → Runtime Monitoring → Configuration
#    - Find: "Automated agent configuration" section
#    - Click: Enable button for "Amazon EC2"
#    - Result: Agent will be deployed via AWS Systems Manager
#
# Why manual configuration is required:
# - AWS does not provide Terraform resources for these agent configurations
# - Only EKS_RUNTIME_MONITORING is available as a detector feature
# - ECS Fargate and EC2 use a different configuration mechanism
#
# Platform Support Summary:
# ├── EKS clusters: ✅ Fully automated via enable_eks_runtime_agent = true
# ├── ECS Fargate: ⚠️ Manual enable in console required
# ├── EC2 instances: ⚠️ Manual enable in console required
# └── ECS EC2 launch type: ❌ NOT supported (use EBS_MALWARE_PROTECTION instead)
# ──────────────────────────────────────────────────────────────────────────────



