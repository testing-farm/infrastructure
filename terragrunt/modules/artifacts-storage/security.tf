# ==============================================================================
# Security Groups for S3 Files Mount Target and NFS Client
# ==============================================================================

resource "aws_security_group" "nfs_client" {
  name        = "${var.name_prefix}-nfs-client-sg"
  description = "Security group for EC2 client mounting S3 Files NFS"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-nfs-client-sg"
    }
  )
}

resource "aws_security_group" "mount_target" {
  name        = "${var.name_prefix}-mount-target-sg"
  description = "Security group for S3 Files mount target"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name_prefix}-mount-target-sg"
    }
  )
}

# Allow EC2 NFS client to reach the mount target on TCP 2049
resource "aws_security_group_rule" "client_egress_to_mount_target" {
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.nfs_client.id
  source_security_group_id = aws_security_group.mount_target.id
  description              = "Allow NFS traffic to S3 Files mount target"
}

# Allow S3 Files mount target to accept NFS connections from the client SG on TCP 2049
resource "aws_security_group_rule" "mount_target_ingress_from_client" {
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  security_group_id        = aws_security_group.mount_target.id
  source_security_group_id = aws_security_group.nfs_client.id
  description              = "Allow NFS traffic from EC2 artifact server client SG"
}
