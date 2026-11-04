# Include terragrunt.hcl from the parent folder
include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "tfr:///terraform-aws-modules/route53/aws//modules/records?version=2.11.1"
}

# Records of the testing.farm zone not tied to a Testing Farm deployment.
# They were created by hand at Spaceship, the registrar, before the zone was delegated to Route53.
inputs = {
  zone_name = "testing.farm"
  records_jsonencoded = jsonencode([
    {
      name    = "fedora-amd.ranch"
      type    = "A"
      ttl     = 300
      records = ["3.80.221.251"]
    },
    {
      name    = "md"
      type    = "CNAME"
      ttl     = 300
      records = ["elb.apps.ospo-osci.z3b1.p1.openshiftapps.com"]
    }
  ])
}
