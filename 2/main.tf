data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_s3_bucket" "backup" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? var.bucket_prefix : null

  tags = merge(
    var.tags,
    {
      Name = var.bucket_name != null ? var.bucket_name : "${var.bucket_prefix}${var.environment}"
    }
  )
}

# Disables ACLs so the bucket owner owns all uploaded objects
resource "aws_s3_bucket_ownership_controls" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Ransomware and accidental deletion protection
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

data "aws_iam_policy_document" "kms_policy" {
  count = var.enable_kms_encryption ? 1 : 0

  statement {
    sid    = "EnableRootKeyManagementAndIAMDelegation"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  # Explicit permission for the uploader role to use the KMS key via S3
  statement {
    sid    = "AllowUploaderRoleKeyUsage"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.uploader_role_arn]
    }
    actions = [
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:Decrypt"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "backup" {
  count                   = var.enable_kms_encryption ? 1 : 0
  description             = "KMS CMK for filesystem backup S3 encryption"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_policy[0].json

  tags = merge(
    var.tags,
    {
      Name = "backup-${var.environment}-kms-key"
    }
  )
}

resource "aws_kms_alias" "backup" {
  count         = var.enable_kms_encryption ? 1 : 0
  name          = "alias/backup-${var.environment}-key"
  target_key_id = aws_kms_key.backup[0].key_id
}

# S3 Bucket Key reduces KMS request costs by ~99%
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.enable_kms_encryption ? "aws:kms" : "AES256"
      kms_master_key_id = var.enable_kms_encryption ? aws_kms_key.backup[0].arn : null
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  # 30 days in Standard, then moves straight into cheapest Glacier storage
  rule {
    id     = "backup-standard-to-glacier-and-180d-expiration"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = var.transition_ia_days != null ? [var.transition_ia_days] : []
      content {
        days          = transition.value
        storage_class = "STANDARD_IA"
      }
    }

    transition {
      days          = var.transition_glacier_days
      storage_class = var.glacier_storage_class
    }

    # Strict Backup Policy: Expire after exactly 180 days (and no more)
    expiration {
      days = var.retention_days
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning && var.transition_ia_days != null ? [var.transition_ia_days] : []
      content {
        noncurrent_days = noncurrent_version_transition.value
        storage_class   = "STANDARD_IA"
      }
    }

    dynamic "noncurrent_version_transition" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = var.transition_glacier_days
        storage_class   = var.glacier_storage_class
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.enable_versioning ? [1] : []
      content {
        noncurrent_days = var.retention_days
      }
    }

    # Cost leak prevention: Abort incomplete multipart uploads after 7 days
    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  rule {
    id     = "cleanup-expired-object-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.backup]
}

# Attaching upload permissions directly to the bucket via its resource-based policy
# decouples the bucket deployment from the IAM role lifecycle and guarantees that
# arn:aws:iam::123456789012:role/backup_uploader is fully authorized to upload.
data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid    = "AllowUploaderRolePutObjects"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.uploader_role_arn]
    }
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload"
    ]
    resources = [
      "${aws_s3_bucket.backup.arn}/*"
    ]
  }

  statement {
    sid    = "AllowUploaderRoleBucketOperations"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.uploader_role_arn]
    }
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [
      aws_s3_bucket.backup.arn
    ]
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*"
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyDeprecatedTLS"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.backup.arn,
      "${aws_s3_bucket.backup.arn}/*"
    ]
    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "backup" {
  bucket     = aws_s3_bucket.backup.id
  policy     = data.aws_iam_policy_document.bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.backup]
}
