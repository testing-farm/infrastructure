terraform {
  required_version = ">=1.2.0"

  required_providers {
    external = {
      version = ">=2.2.0"
    }
  }
}

# Public IP of localhost, used for development access to Artemis API and provisioned guests
data "external" "localhost_public_ip" {
  program = [
    "sh",
    "-c",
    "jq -n --arg output \"$(curl -4s icanhazip.com)\" '{$output}'"
  ]
}
