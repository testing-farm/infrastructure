# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

# DNS records for services on the Red Hat ranch server (testing_farm_redhat_server_01).
# The server is not managed by terraform and has only a private IP, so the address is hard-coded.
# The records resolve publicly but are reachable only from the Red Hat network.
inputs = {
  zone_name = "testing.farm"
  records_jsonencoded = jsonencode([
    {
      name    = "tmt.redhat"
      type    = "A"
      ttl     = 300
      records = ["10.29.163.102"]
    }
  ])
}
