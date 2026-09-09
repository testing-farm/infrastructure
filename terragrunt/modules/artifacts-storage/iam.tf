data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ==============================================================================
# S3 Files Service Role
# Assumed by elasticfilesystem.amazonaws.com for bucket synchronization and events
# ==============================================================================

data "aws_iam_policy_document" "s3files_service_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["elasticfilesystem.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:s3files:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:file-system/*"]
    }
  }
}

resource "aws_iam_role" "s3files_service" {
  name               = "${var.name_prefix}-s3files-service-role"
  assume_role_policy = data.aws_iam_policy_document.s3files_service_assume_role.json

  tags = var.tags
}

#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "s3files_service" {
  # Bucket synchronization object actions
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject*",
      "s3:PutObject*",
      "s3:DeleteObject*",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }

  # Bucket synchronization bucket actions
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketVersioning",
      "s3:GetBucketLocation"
    ]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  # EventBridge rules management for synchronization event notifications
  statement {
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:PutTargets",
      "events:DeleteRule",
      "events:RemoveTargets",
      "events:EnableRule",
      "events:DisableRule"
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/DO-NOT-DELETE-S3-Files*"
    ]

    condition {
      test     = "StringEquals"
      variable = "events:ManagedBy"
      values   = ["elasticfilesystem.amazonaws.com"]
    }
  }

  # Rule reads do not support the events:ManagedBy condition
  statement {
    effect = "Allow"
    actions = [
      "events:DescribeRule",
      "events:ListTargetsByRule"
    ]
    resources = [
      "arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:rule/*"
    ]
  }

  # These list actions do not support resource-level permissions
  statement {
    effect = "Allow"
    actions = [
      "events:ListRuleNamesByTarget",
      "events:ListRules"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "s3files_service" {
  name   = "${var.name_prefix}-s3files-service-policy"
  role   = aws_iam_role.s3files_service.name
  policy = data.aws_iam_policy_document.s3files_service.json
}

# ==============================================================================
# EC2 Client Role & Instance Profile
# Assumed by the EC2 server mounting S3 Files and serving artifacts
# ==============================================================================

data "aws_iam_policy_document" "ec2_client_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_client" {
  name               = "${var.name_prefix}-ec2-client-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_client_assume_role.json

  tags = var.tags
}

# AWS Managed Policy for S3 Files Client operations
resource "aws_iam_role_policy_attachment" "ec2_client_s3files" {
  role       = aws_iam_role.ec2_client.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FilesClientFullAccess"
}

# S3 direct access permissions for EC2 client (for large object read-through & listing)
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "ec2_client_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject*"
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ec2_client_s3" {
  name   = "${var.name_prefix}-ec2-client-s3-policy"
  role   = aws_iam_role.ec2_client.name
  policy = data.aws_iam_policy_document.ec2_client_s3.json
}

resource "aws_iam_instance_profile" "ec2_client" {
  name = "${var.name_prefix}-instance-profile"
  role = aws_iam_role.ec2_client.name

  tags = var.tags
}
