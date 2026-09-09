# ==============================================================================
# AWS S3 Files Filesystem and Mount Target
# ==============================================================================

data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_s3files_file_system" "artifacts" {
  bucket   = aws_s3_bucket.artifacts.arn
  role_arn = aws_iam_role.s3files_service.arn

  # Explicit dependency on prerequisite bucket configurations and IAM policy attachment
  depends_on = [
    aws_s3_bucket_versioning.artifacts,
    aws_s3_bucket_server_side_encryption_configuration.artifacts,
    aws_s3_bucket_public_access_block.artifacts,
    aws_iam_role_policy.s3files_service
  ]

  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

resource "aws_s3files_mount_target" "artifacts" {
  file_system_id  = aws_s3files_file_system.artifacts.id
  subnet_id       = var.subnet_id
  security_groups = [aws_security_group.mount_target.id]
}
