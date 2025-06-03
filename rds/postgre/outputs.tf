# outputs.tf
output "rds_instance" {
  description = "Details of the PostgreSQL RDS instance created"
  value = {
    db_instance_identifier = aws_db_instance.postgres_db_instance.id
    db_instance_endpoint   = aws_db_instance.postgres_db_instance.endpoint
    db_instance_arn        = aws_db_instance.postgres_db_instance.arn
    db_name                = aws_db_instance.postgres_db_instance.db_name
    db_username            = aws_db_instance.postgres_db_instance.username
    db_password            = aws_db_instance.postgres_db_instance.password
    db_instance_ips        = aws_db_instance.postgres_db_instance.address
    vpc_security_group_ids = aws_db_instance.postgres_db_instance.vpc_security_group_ids
  }
  sensitive = true
}