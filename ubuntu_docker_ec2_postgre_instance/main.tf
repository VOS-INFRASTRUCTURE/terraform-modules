
locals {
  instance_name = "${var.project_id}-${var.env}-${var.base_name}-ec2"
}

resource "tls_private_key" "rsa_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}


resource "aws_instance" "docker_ec2" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  user_data = <<-EOF
              #!/bin/bash -xe
              apt-get update -y
              apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg-agent git

              # Install Docker
              curl -fsSL https://get.docker.com -o get-docker.sh
              sh get-docker.sh
              systemctl start docker
              systemctl enable docker

              # Install Docker Compose
              apt-get install -y docker-compose

              # Add the current user to the Docker group
              usermod -aG docker ubuntu

              # Provision SSH public key
              mkdir -p /home/ubuntu/.ssh
              echo "${tls_private_key.rsa_key.private_key_pem}" > /home/ubuntu/.ssh/id_rsa
              echo "${tls_private_key.rsa_key.public_key_openssh}" > /home/ubuntu/.ssh/id_rsa.pub

              # Add public key ssh to authorized keys
              echo "${tls_private_key.rsa_key.public_key_openssh}" >> /home/ubuntu/.ssh/authorized_keys

              echo "${tls_private_key.rsa_key.private_key_pem}" > /home/ubuntu/.ssh/id_rsa.private_key_pem
              echo "${tls_private_key.rsa_key.public_key_pem}" > /home/ubuntu/.ssh/id_rsa.public_key_pem
              echo "${tls_private_key.rsa_key.private_key_openssh}" > /home/ubuntu/.ssh/id_rsa.private_key_openssh
              chmod 600 /home/ubuntu/.ssh/id_rsa
              chmod 600 /home/ubuntu/.ssh/authorized_keys
              chown -R ubuntu:ubuntu /home/ubuntu/.ssh

              # Define PostgreSQL startup script (no env vars needed now)
              cat <<'SCRIPT' > /usr/local/bin/start_postgres_container.sh
              #!/bin/bash
              docker run -d \
                --name postgres-server \
                -e POSTGRES_DB="${var.postgresql_config.db_name}" \
                -e POSTGRES_USER="${var.postgresql_config.db_username}" \
                -e POSTGRES_PASSWORD="${var.postgresql_config.db_password}" \
                -p 5432:5432 \
                -v postgres_data_volume:/var/lib/postgresql/data \
                --restart always \
                postgres:${var.postgresql_config.db_engine_version}
              SCRIPT

              chmod +x /usr/local/bin/start_postgres_container.sh

              # Run the container
              /usr/local/bin/start_postgres_container.sh

              # Ensure it runs on reboot (no env vars needed now)
              (crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/start_postgres_container.sh") | crontab -

              echo "PostgreSQL Docker setup completed successfully."
              EOF


  root_block_device {
    volume_size = var.storage_size
    volume_type = var.storage_type
  }

  ebs_optimized = true

  tags = merge(
    var.tags,
    {
      Name        = local.instance_name
      Environment = var.env
    }
  )
}
