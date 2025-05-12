terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.81.0"
    }
  }
}
# Elastic IP creation

locals {
  local_eip_name = "${var.project_id}-${var.env}-${var.eip_name}-eip"
}

resource "aws_eip" "elastic_ip" {
  domain   = "vpc"

  tags = {
    Name = local.local_eip_name
  }
}