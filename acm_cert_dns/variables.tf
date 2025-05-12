variable "domain_name" {
  description = "The root domain name (e.g. example.com)"
  type        = string
}

variable "hosted_zone_id" {
  description = "The Route 53 hosted zone ID"
  type        = string
}

variable "environment" {
  description = "Environment name for tagging (e.g. dev, prod)"
  type        = string
}
