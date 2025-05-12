# Output the Key Pair Details
output "key_pair_details" {
  description = "Details of the created key pair"
  value = {
    key_name         = aws_key_pair.key_pair.key_name
    private_key_path = "${aws_key_pair.key_pair.key_name}.pem"
  }
}

output "key_pair_sensitive_details" {
  description = "Details of the keys of the key pair"
  value = {
    private_key_pem  = tls_private_key.tls_prv_key.private_key_pem
    public_key_pem  = tls_private_key.tls_prv_key.public_key_pem
    private_key_openssh  = tls_private_key.tls_prv_key.private_key_openssh
    public_key_openssh  = tls_private_key.tls_prv_key.public_key_openssh
  }
  sensitive = true
}