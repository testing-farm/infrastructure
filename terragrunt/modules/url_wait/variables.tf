variable "urls" {
  description = "List of URLs to wait for."
  type        = list(string)
}

variable "timeout" {
  description = "Maximum time to wait for each URL in seconds."
  type        = number
  # Default timeout of 5 minutes
  default = 300
}
