# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

# Records of the testing-farm.io zone for services on the Public ranch server (testing_farm_public_server_01).
# The server is not managed by terraform, so its EC2 hostname is hard-coded.
#
# The records were created by hand, import them before the first apply:
#
#   terragrunt import 'aws_route53_record.this["tmt CNAME"]' Z0711647188EWQGM661TT_tmt.testing-farm.io_CNAME
inputs = {
  zone_name = "testing-farm.io"
  records_jsonencoded = jsonencode([
    # Redirects to tmt.public.testing.farm
    {
      name    = "tmt"
      type    = "CNAME"
      ttl     = 60
      records = ["ec2-52-14-131-2.us-east-2.compute.amazonaws.com"]
    }
  ])
}
