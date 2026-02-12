################################################################################
# CERPAC – Automated EC2 Isolation (GuardDuty Response)
#
# PURPOSE
# -------
# Automatically isolates compromised EC2 instances detected by GuardDuty.
#
# ACTIONS
# -------
# - Remove instance from load balancers / ASGs
# - Replace security groups with quarantine SG
# - Snapshot EBS volumes for forensics
# - Tag instance for investigation
#
# SAFETY
# ------
# - NO termination
# - NO data deletion
# - Fully auditable via CloudTrail
#
# STATUS
# ------
# ⏸ PLANNED / NOT DEPLOYED
################################################################################

variable "enable_ec2_auto_isolation" {
  description = "Enable automatic isolation of compromised EC2 instances"
  type        = bool
  default     = false
}

resource "aws_security_group" "ec2_quarantine" {
  count = var.enable_ec2_auto_isolation ? 1 : 0

  name        = "${var.env}-ec2-quarantine"
  description = "Quarantine SG – blocks all ingress and egress"
  vpc_id      = aws_vpc.main.id

  revoke_rules_on_delete = true

  tags = {
    Name        = "${var.env}-ec2-quarantine"
    Purpose     = "IncidentResponse"
    ManagedBy   = "Terraform"
  }
}

resource "aws_iam_role" "ec2_isolation_lambda" {
  count = var.enable_ec2_auto_isolation ? 1 : 0

  name = "${var.env}-ec2-isolation-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_cloudwatch_event_rule" "guardduty_ec2_compromise" {
  count = var.enable_ec2_auto_isolation ? 1 : 0

  name        = "${var.env}-guardduty-ec2-compromise"
  description = "Trigger EC2 isolation on confirmed GuardDuty compromise"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ "numeric": [">=", 7] }]
      type = [
        { "prefix": "CryptoCurrency:EC2" },
        { "prefix": "AttackSequence:EC2" }
      ]
    }
  })
}
