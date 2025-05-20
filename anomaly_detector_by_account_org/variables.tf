variable "linked_accounts" {
  description = "List of linked AWS accounts to monitor"
  type = list(object({
    id   = string
    name = string
  }))
}

variable "alert_email" {
  description = "Email address to receive anomaly alerts"
  type        = string
}

variable "threshold_percentage" {
  description = "Percentage threshold to trigger anomaly alerts"
  type        = number
  default     = 5
}
