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