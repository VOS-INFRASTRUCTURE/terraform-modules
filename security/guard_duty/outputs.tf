################################################################################
# GuardDuty Module Outputs
#
# All outputs are consolidated into a single 'guardduty' object for easier
# consumption and cleaner code organization.
#
# Usage:
#   module.guardduty.guardduty.detector.id
#   module.guardduty.guardduty.features.s3_data_events
#   module.guardduty.guardduty.summary.total_features_enabled
################################################################################

output "guard_duty" {
  description = "GuardDuty resources and configuration details"
  value = var.enable_guardduty ? {
    # ──────────────────────────────────────────────────────────────────────
    # Detector - Core GuardDuty threat detection service
    # ──────────────────────────────────────────────────────────────────────
    detector = {
      id                           = aws_guardduty_detector.this[0].id                           # Detector ID
      arn                          = aws_guardduty_detector.this[0].arn                          # Detector ARN
      account_id                   = aws_guardduty_detector.this[0].account_id                   # AWS account ID
      finding_publishing_frequency = var.finding_publishing_frequency                            # How often findings are published
      status                       = "ENABLED"                                                   # Detector status
    }

    # ──────────────────────────────────────────────────────────────────────
    # Data Sources - What GuardDuty monitors
    # ──────────────────────────────────────────────────────────────────────
    data_sources = {
      cloudtrail       = true                                      # Always enabled (API call monitoring)
      vpc_flow_logs    = true                                      # Always enabled (network traffic)
      dns_logs         = true                                      # Always enabled (DNS query analysis)
      s3_logs          = var.enable_s3_data_events                 # S3 data event monitoring
      kubernetes_logs  = var.enable_eks_audit_logs                 # EKS audit log analysis
      malware_scanning = var.enable_ebs_malware_protection         # EBS volume malware scanning
    }

    # ──────────────────────────────────────────────────────────────────────
    # Protection Features - Advanced threat detection capabilities
    # ──────────────────────────────────────────────────────────────────────
    features = {
      s3_data_events          = var.enable_s3_data_events           # S3 object-level monitoring
      eks_audit_logs          = var.enable_eks_audit_logs           # Kubernetes API monitoring
      rds_login_events        = var.enable_rds_protection           # Database login monitoring
      lambda_network_logs     = var.enable_lambda_protection        # Lambda network monitoring
      ebs_malware_protection  = var.enable_ebs_malware_protection   # EBS malware scanning (GuardDuty-initiated)
      eks_runtime_monitoring  = var.enable_runtime_monitoring       # EKS runtime monitoring
      runtime_monitoring      = var.enable_runtime_monitoring       # EKS/ECS Fargate runtime monitoring
    }

    # ──────────────────────────────────────────────────────────────────────
    # Malware Protection Summary
    # ──────────────────────────────────────────────────────────────────────
    malware_protection = {
      ec2_ebs_scanning = var.enable_ebs_malware_protection    # EC2: GuardDuty-initiated EBS scans
      # Note: S3 malware scanning is not available via aws_guardduty_detector_feature
      #       Must be configured manually in AWS Console or via different resource
      # Note: AWS Backup malware scanning is not yet supported via Terraform
      #       Must be configured manually in the AWS Console
    }

    # ──────────────────────────────────────────────────────────────────────
    # Configuration Summary - Quick reference
    # ──────────────────────────────────────────────────────────────────────
    summary = {
      module_enabled         = true                                                               # Module is active
      environment            = var.env                                                            # Environment name
      project_id             = var.project_id                                                     # Project identifier
      total_features_enabled = (
        (var.enable_s3_data_events ? 1 : 0) +
        (var.enable_eks_audit_logs ? 1 : 0) +
        (var.enable_rds_protection ? 1 : 0) +
        (var.enable_lambda_protection ? 1 : 0) +
        (var.enable_ebs_malware_protection ? 1 : 0) +
        (var.enable_runtime_monitoring ? 1 : 0)
        # Note: S3 malware protection not counted as it's not a detector feature
      )
    }
  } : null
}

