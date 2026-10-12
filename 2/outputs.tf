output "bucket_id" {
  description = "The name / ID of the backup S3 bucket."
  value       = aws_s3_bucket.backup.id
}

output "bucket_arn" {
  description = "The ARN of the backup S3 bucket."
  value       = aws_s3_bucket.backup.arn
}

output "bucket_region" {
  description = "The AWS Region where the backup S3 bucket is hosted."
  value       = data.aws_region.current.region
}

output "kms_key_arn" {
  description = "The ARN of the Customer Managed KMS Key used for server-side encryption."
  value       = var.enable_kms_encryption ? aws_kms_key.backup[0].arn : null
}

output "kms_key_alias" {
  description = "The alias of the KMS Key used for backup encryption."
  value       = var.enable_kms_encryption ? aws_kms_alias.backup[0].name : null
}

output "uploader_role_arn" {
  description = "The IAM role granted upload permissions directly via the S3 Bucket Policy."
  value       = var.uploader_role_arn
}

output "retention_policy_days" {
  description = "Strict retention limit in days before permanent expiration."
  value       = var.retention_days
}

output "lifecycle_tiering_summary" {
  description = "Summary of the lifecycle transition and expiration stages."
  value = {
    standard_duration_days = "0 to ${var.transition_glacier_days}"
    intermediate_ia_tier   = var.transition_ia_days != null ? "Day ${var.transition_ia_days}" : "None (straight to Glacier)"
    glacier_storage_class  = var.glacier_storage_class
    glacier_transition     = "Day ${var.transition_glacier_days}"
    permanent_deletion     = "Day ${var.retention_days}"
    multipart_abort_days   = "Day ${var.abort_incomplete_multipart_upload_days}"
  }
}
