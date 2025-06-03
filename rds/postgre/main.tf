
locals {
  postgre_full_name = "${var.project_id}-${var.env}-${var.db_name}-postgres"
}


# Resource declaration for the RDS Subnet Group
resource "aws_db_subnet_group" "postgres_rds_subnet_group" {
  name        = "${local.postgre_full_name}-sg"
  description = "Subnet group for PostgreSQL RDS instances in private subnets for ${var.env}"
  subnet_ids  = var.subnet_ids

  tags = {
    Environment = var.env
    Name        = "${local.postgre_full_name}-sg"
  }
}

# Resource declaration for the PostgreSQL RDS instance
resource "aws_db_instance" "postgres_db_instance" {
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  engine                 = "postgres"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = var.publicly_accessible
  db_subnet_group_name   = aws_db_subnet_group.postgres_rds_subnet_group.name
  vpc_security_group_ids = var.vpc_security_group_ids
  multi_az               = var.multi_az
  skip_final_snapshot    = var.skip_final_snapshot

  tags = {
    Environment = var.env
    Name        = local.postgre_full_name
  }
}

