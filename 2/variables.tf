variable "aws_region" {
  description = "AWS Region where the backup bucket and KMS key are deployed."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Environment identifier (e.g., prod, staging, dev)."
  type        = string
  default     = "prod"
}

variable "bucket_name" {
  description = "Explicit name for the S3 backup bucket. If null, bucket_prefix will be used."
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "Prefix for the S3 backup bucket name if bucket_name is not provided."
  type        = string
  default     = "app-backups-archive-"
}

variable "uploader_role_arn" {
  description = "ARN of the preexisting IAM role authorized to upload backups (permissions attached via Bucket Policy)."
  type        = string
  default     = "arn:aws:iam::123456789012:role/backup_uploader"
}

variable "retention_days" {
  description = "Maximum duration (in days) backups are retained before permanent deletion. Must satisfy 180 days policy."
  type        = number
  default     = 180

  validation {
    condition     = var.retention_days == 180
    error_message = "Backup retention policy strictly requires storing backups for 180 days and no more."
  }
}

variable "transition_glacier_days" {
  description = "Number of days in S3 Standard before moving straight into Glacier storage. Default is 30 days."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_glacier_days > 0 && var.transition_glacier_days < var.retention_days
    error_message = "transition_glacier_days must be greater than 0 and less than retention_days (180)."
  }
}

variable "glacier_storage_class" {
  description = "The target Glacier storage class. Defaults to DEEP_ARCHIVE (cheapest S3 storage tier)."
  type        = string
  default     = "DEEP_ARCHIVE"

  validation {
    condition     = contains(["DEEP_ARCHIVE", "GLACIER", "GLACIER_IR"], var.glacier_storage_class)
    error_message = "glacier_storage_class must be one of: DEEP_ARCHIVE, GLACIER, GLACIER_IR."
  }
}

variable "transition_ia_days" {
  description = "Optional number of days before transitioning to S3 Standard-IA. Set to null by default (moves straight into Glacier)."
  type        = number
  default     = null

  validation {
    condition     = var.transition_ia_days == null || (can(var.transition_ia_days >= 30) && can(var.transition_ia_days < var.transition_glacier_days))
    error_message = "If specified, transition_ia_days must be at least 30 days and less than transition_glacier_days."
  }
}

variable "enable_versioning" {
  description = "Enable S3 versioning to guard against accidental deletion or ransomware overwrites."
  type        = bool
  default     = true
}

variable "enable_kms_encryption" {
  description = "Enable Customer Managed KMS Key (CMK) encryption. If false, standard AES256 (SSE-S3) is used."
  type        = bool
  default     = true
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period (in days) before KMS key deletion."
  type        = number
  default     = 30
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after which incomplete multipart uploads are aborted to prevent cost leaks."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Default resource tags to assign to all provisioned resources."
  type        = map(string)
  default = {
    Project     = "Filesystem Backup Storage"
    ManagedBy   = "Terraform"
    Compliance  = "180-day-retention"
    Environment = "prod"
  }
}
