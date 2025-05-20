variable "thresholds" {
  description = "List of billing thresholds in USD"
  type        = list(number)
  default     = [6, 10, 15, 30, 100, 150, 200]
}

variable "alert_emails" {
  description = "List of emails to receive billing alerts"
  type        = list(string)
  default     = ["ibukunoreofe@gmail.com"]
}
