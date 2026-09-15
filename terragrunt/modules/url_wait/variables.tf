variable "urls" {
  description = "List of URLs to wait for."
  type        = list(string)
}

variable "timeout" {
  description = "Maximum time to wait for each URL in seconds."
  type        = number
  # Default timeout of 15 minutes
  #
  # NOTE: a recreated server has to boot, pull the pod images and restore the
  # database dump before nginx answers, which can take well over 5 minutes.
  # Waiting longer is free: the loop exits as soon as the URL responds, so this
  # only bounds how long a genuinely broken deployment takes to fail.
  default = 900
}
