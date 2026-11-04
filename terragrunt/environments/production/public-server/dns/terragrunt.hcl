# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

# DNS records for services on the Public ranch server (testing_farm_public_server_01).
# The server is not managed by terraform, so its EC2 hostname is hard-coded.
inputs = {
  zone_name = "testing.farm"
  records_jsonencoded = jsonencode([
    {
      name    = "tmt.public"
      type    = "CNAME"
      ttl     = 60
      records = ["ec2-52-14-131-2.us-east-2.compute.amazonaws.com"]
    }
  ])
}
