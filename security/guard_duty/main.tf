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
# S3 Malware Protection (Object-Level Scanning)
#
# AWS Console: Protection Plans → Malware Protection → S3
#
# Purpose: Scan new S3 uploads for malware in real-time
#
# How it works:
# 1. Configure specific S3 buckets for scanning
# 2. New objects uploaded to these buckets are automatically scanned
# 3. Malware findings published to GuardDuty console
# 4. Can trigger automatic remediation (quarantine, delete, etc.)
#
# What it detects:
# - Known malware signatures
# - Trojans, ransomware, viruses
# - Suspicious executable files
# - Malicious scripts
#
# Cost: Varies by usage (pay per scan)
#
# Note: This is DIFFERENT from enable_s3_data_events:
#   - S3_DATA_EVENTS: Monitors access patterns (who accessed what, when)
#   - S3_MALWARE_SCANNING: Scans file contents for malware
#
# Important: After enabling, you must configure which S3 buckets to scan
#            via the GuardDuty console or additional Terraform resources.
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "s3_malware_protection" {
  count = var.enable_guardduty ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "S3_MALWARE_SCANNING"
  status      = var.enable_s3_malware_protection ? "ENABLED" : "DISABLED"
}

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
# Runtime Monitoring - EKS Runtime Monitoring (Sub-feature)
#
# AWS Console: Protection Plans → Runtime Monitoring → EKS Add-on Management
#
# Purpose: Automatically manage GuardDuty agent on EKS clusters
#
# When enabled with RUNTIME_MONITORING:
# - GuardDuty automatically deploys agent to EKS clusters
# - Handles agent updates and lifecycle
# - Simplifies deployment (no manual kubectl commands)
#
# When disabled:
# - You must manually deploy the GuardDuty agent
# - More control but requires manual maintenance
#
# Note: This is a separate feature from the main RUNTIME_MONITORING feature.
#       It specifically handles EKS cluster monitoring.
#
# Recommendation: Keep enabled if you enabled runtime_monitoring and have EKS clusters
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "eks_runtime_monitoring" {
  count = var.enable_guardduty && var.enable_runtime_monitoring ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_RUNTIME_MONITORING"
  status      = var.enable_runtime_monitoring ? "ENABLED" : "DISABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Note: ECS Fargate Runtime Monitoring
#
# AWS Console: Protection Plans → Runtime Monitoring → ECS Fargate Agent Management
#
# ECS Fargate runtime monitoring is automatically included when you enable
# the main RUNTIME_MONITORING feature above. There is no separate feature flag
# for ECS Fargate specifically.
#
# When RUNTIME_MONITORING is enabled:
# - ✅ EKS clusters: Agent automatically deployed
# - ✅ ECS Fargate tasks: Agent automatically injected
# - ❌ ECS EC2 instances: NOT supported (use EBS_MALWARE_PROTECTION instead)
#
# Important: ECS Launch Type Support
# ✅ ECS Fargate (serverless): SUPPORTED - Agent auto-injected into tasks
# ❌ ECS EC2 (container instances): NOT SUPPORTED - Use EBS_MALWARE_PROTECTION instead
#
# Why the difference?
# - Fargate: AWS controls the infrastructure, can inject agent automatically
# - EC2: You control the instances, agent injection not possible
# - For EC2 instances: GuardDuty scans EBS volumes instead of runtime monitoring
# ──────────────────────────────────────────────────────────────────────────────



