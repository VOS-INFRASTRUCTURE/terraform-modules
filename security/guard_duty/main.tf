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

  # Enable EBS volume scanning for malware (additional cost)
  datasources {
    s3 {
      enable = var.enable_s3_protection
    }

    kubernetes {
      audit_logs {
        enable = var.enable_eks_protection
      }
    }

    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.enable_malware_protection
        }
      }
    }
  }

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
# Purpose: Monitor S3 object-level API calls for suspicious activity
#
# Detects:
# - Data exfiltration (unusual download patterns)
# - Malware uploads
# - Ransomware activity
# - Suspicious S3 access patterns
#
# Cost: ~$0.20 per GB of S3 data analyzed
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "s3_data_events" {
  count = var.enable_guardduty && var.enable_s3_data_events ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# EKS Audit Logs Protection
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
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "eks_audit_logs" {
  count = var.enable_guardduty && var.enable_eks_audit_logs ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EKS_AUDIT_LOGS"
  status      = "ENABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# RDS Login Activity Protection
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
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "rds_login_events" {
  count = var.enable_guardduty && var.enable_rds_protection ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "RDS_LOGIN_EVENTS"
  status      = "ENABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda Network Activity Protection
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
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "lambda_network_logs" {
  count = var.enable_guardduty && var.enable_lambda_protection ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "LAMBDA_NETWORK_LOGS"
  status      = "ENABLED"
}

# ──────────────────────────────────────────────────────────────────────────────
# EBS Malware Protection
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
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  count = var.enable_guardduty && var.enable_ebs_malware_protection ? 1 : 0

  detector_id = aws_guardduty_detector.this[0].id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

