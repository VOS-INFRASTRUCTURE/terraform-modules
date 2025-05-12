
output "instance_details" {
  description = "Details of the launched EC2 instance with MySQL"
  value = {
    instance_id        = aws_instance.docker_ec2.id
    instance_id        = aws_instance.docker_ec2.id
    public_ip          = aws_instance.docker_ec2.public_ip
    private_ip         = aws_instance.docker_ec2.private_ip
    ami_id             = aws_instance.docker_ec2.ami
    instance_type      = aws_instance.docker_ec2.instance_type
    security_group_ids = aws_instance.docker_ec2.vpc_security_group_ids
    tags               = aws_instance.docker_ec2.tags

    ssh_public_key     = tls_private_key.rsa_key.public_key_openssh
    ssh_private_key     = tls_private_key.rsa_key.private_key_pem

    db_info             = {
      mysql_database = var.mysql_database
      mysql_user = var.mysql_user
      mysql_password = var.mysql_password
      mysql_root_password = var.mysql_root_password
    }
  }
  sensitive = true
}