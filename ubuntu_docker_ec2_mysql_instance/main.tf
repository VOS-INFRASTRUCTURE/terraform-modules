
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

              # Install Docker using the official convenience script
              curl -fsSL https://get.docker.com -o get-docker.sh
              sh get-docker.sh

              # Start and enable Docker service
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

              chmod 600 /home/ubuntu/.ssh/authorized_keys
              chmod 600 /home/ubuntu/.ssh/id_rsa
              chown -R ubuntu:ubuntu /home/ubuntu/.ssh

              # Create a startup script for MySQL container
              cat <<'SCRIPT' > /usr/local/bin/start_mysql_container.sh
              #!/bin/bash
              docker run -d \
                --name mysql-server \
                -e MYSQL_ROOT_PASSWORD=${var.mysql_root_password} \
                -e MYSQL_DATABASE=${var.mysql_database} \
                -e MYSQL_USER=${var.mysql_user} \
                -e MYSQL_PASSWORD=${var.mysql_password} \
                -v /home/ubuntu/mysql_data:/var/lib/mysql \
                -p 3306:3306 \
                --restart always \
                mysql:8
              SCRIPT
              chmod +x /usr/local/bin/start_mysql_container.sh

              # Add startup script to crontab for reboot
              (crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/start_mysql_container.sh") | crontab -

              # Run the MySQL container immediately
              /usr/local/bin/start_mysql_container.sh

              # Verify installations
              docker --version
              docker-compose --version
              git --version

              echo "User data script completed successfully."
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
