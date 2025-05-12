
locals {
  key_name = "${var.project_id}-${var.env}-${var.vpc_id}-keypair"
}
# Terraform Code to Create and Manage Key Pair

# Generate a Private Key
resource "tls_private_key" "tls_prv_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create an AWS Key Pair Using the Generated Public Key
resource "aws_key_pair" "key_pair" {
  key_name   = local.key_name
  public_key = tls_private_key.tls_prv_key.public_key_openssh
}

# # No need since it is remote
# # Store the Private Key Locally (Optional but Secure)
# resource "local_file" "private_key" {
#   filename        = "${local.key_name}.pem"
#   content         = tls_private_key.tls_prv_key.private_key_pem
#   file_permission = "0600" # Restrict access to the private key file
# }
