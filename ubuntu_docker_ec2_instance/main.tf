
locals {
  resource_prefix = "${var.project_id}-${var.env}"
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
              chmod 600 /home/ubuntu/.ssh/id_rsa
              chmod 600 /home/ubuntu/.ssh/authorized_keys
              chown -R ubuntu:ubuntu /home/ubuntu/.ssh

              # Create a custom HTML file
              mkdir -p /var/www
              chown -R ubuntu:ubuntu /var/www

              mkdir -p /usr/share/nginx/html
              echo "<html><body><h1>Hello from ${local.instance_name}</h1></body></html>" > /usr/share/nginx/html/index.html

              # Run Nginx container with a bind mount to serve the custom HTML
              docker run -d -p 80:80 --name nginx-server -v /usr/share/nginx/html:/usr/share/nginx/html nginx:latest

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