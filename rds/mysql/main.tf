# Resource declaration for the RDS Subnet Group
resource "aws_db_subnet_group" "mysql_rds_subnet_group" {
  name        = "${var.environment}-rds-subnet-group"
  description = "Subnet group for RDS instances in private subnets for ${var.environment}"
  subnet_ids  = var.subnet_ids

  tags = {
    Environment = var.environment
    Name        = "${var.environment}-rds-subnet-group"
  }
}

# Resource declaration for the MySQL RDS instance
resource "aws_db_instance" "mysql_db_instance" {
  allocated_storage      = var.allocated_storage
  max_allocated_storage  = var.max_allocated_storage
  engine                 = "mysql"
  engine_version         = var.db_engine_version
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.mysql_rds_subnet_group.name
  vpc_security_group_ids = var.vpc_security_group_ids
  multi_az               = var.multi_az
  skip_final_snapshot    = var.skip_final_snapshot

  tags = {
    Environment = var.environment
    Name        = "${var.environment}-mysql-${var.db_name}"
  }
}
