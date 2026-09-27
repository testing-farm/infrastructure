# Apply the release-only selector before choosing the newest image; MR uploads are not eligible.
data "aws_ami" "artifacts" {
  most_recent = true
  owners      = ["self"]
  name_regex  = var.ami_name_regex

  filter {
    name   = "name"
    values = [var.ami_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.1"

  name                        = var.name
  ami                         = data.aws_ami.artifacts.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = var.associate_public_ip_address
  enable_volume_tags          = var.enable_volume_tags
  iam_instance_profile        = var.iam_instance_profile
  vpc_security_group_ids      = var.vpc_security_group_ids
  root_block_device           = var.root_block_device
  metadata_options            = var.metadata_options
}

# Preserve an existing instance's state address when introducing the AMI lookup wrapper.
moved {
  from = aws_instance.this
  to   = module.instance.aws_instance.this
}
