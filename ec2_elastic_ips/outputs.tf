output "eip_details" {
  description = "The Elastic IP address"
  value       = {
    public_ip = aws_eip.elastic_ip.public_ip
    elastic_id = aws_eip.elastic_ip.id,
    allocation_id = aws_eip.elastic_ip.allocation_id,
  }
}
