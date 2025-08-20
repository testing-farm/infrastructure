terraform {
  required_version = ">=1.2.0"

  required_providers {
    external = {
      version = ">=2.2.0"
    }
  }
}

# Public IP of localhost, used for development access to Artemis API and provisioned guests.
# Run the resolving of public IP addresses multiple times, in case somebody has multiple providers
# and load balancing between them.
data "external" "localhost_public_ips" {
  program = [
    "sh",
    "-c",
    "jq -n --arg output \"$(for i in {1..10}; do curl -4s icanhazip.com; done | sort | uniq)\" '{$output}'"
  ]
}
