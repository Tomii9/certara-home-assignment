# Enterprise S3 Backup Storage with 180-Day Retention

## 1. Overview & Scenario

This Terraform project provisions a secure, cost-optimized AWS S3 backup storage architecture for filesystem backups within a **single preexisting AWS account**.

### Business & Technical Requirements
- **Strict Retention Policy**: Backups must be retained for **180 days and no more**.
- **Tiering Lifecycle Policy**: Backups reside in **S3 Standard for 30 days**, then transition **straight into the cheapest Glacier storage tier** (`DEEP_ARCHIVE` by default, configurable).
- **Single Preexisting Account**: All resources (S3 backup bucket, KMS encryption key, and application workload) reside within the same AWS account.
- **Bucket-Attached Upload Permissions**: Upload permissions are attached **directly to the bucket itself** via an S3 Bucket Policy for `arn:aws:iam::123456789012:role/backup_uploader`.
- **Architectural Principles**: Adheres to the AWS Well-Architected Framework for **Security**, **Cost Optimization**, and **Compliance**.

---

## 2. Architecture & Data Flow

```
+---------------------------------------------------------------------------------+
| Single AWS Account (Preexisting)                                                |
|                                                                                 |
|   +-------------------------------------------------+                           |
|   | Preexisting IAM Role:                           |                           |
|   | arn:aws:iam::123456789012:role/backup_uploader  |                           |
|   +-------------------------------------------------+                           |
|                            |                                                    |
|                            | 1. Authenticated HTTPS Upload                      |
|                            |    (TLS 1.2+, SSE-KMS)                             |
|                            v                                                    |
|   +-------------------------------------------------+   +---------------------+ |
|   | Amazon S3 Backup Bucket                         |   | AWS KMS CMK         | |
|   | - Bucket Policy (Permissions Attached to Bucket)|   | - Auto Key Rotation | |
|   |   * s3:PutObject, s3:AbortMultipartUpload       |   | - Root IAM          | |
|   |   * s3:ListBucket, s3:GetBucketLocation         |   |   Delegation        | |
|   |   * Deny HTTP & TLS < 1.2                       |<--| - S3 Service Usage  | |
|   | - Public Access Block: All 4 enabled            |   +---------------------+ |
|   | - Object Ownership: BucketOwnerEnforced         |                           |
|   | - S3 Versioning: Enabled                        |                           |
|   | - S3 Bucket Key: Enabled (~99% KMS savings)     |                           |
|   +-------------------------------------------------+                           |
|                            |                                                    |
|                            | S3 Lifecycle Policy (30d Standard -> Glacier)      |
|                            v                                                    |
|   +-------------------------------------------------+                           |
|   | Day 0 to 30:   S3 Standard (Immediate restore)  |                           |
|   | Day 30 to 180: S3 Glacier Deep Archive          |                           |
|   |                (Cheapest storage class: ~95% sv)|                           |
|   | Day 180:       Permanent Expiration (Deletion)  |                           |
|   +-------------------------------------------------+                           |
+---------------------------------------------------------------------------------+
```

---

## 3. Security Best Practices

### A. Bucket-Attached Upload Permissions (Resource-Based Policy)
* **Decoupled Architecture**: Upload permissions are attached directly to the bucket itself via its S3 Bucket Policy (`aws_s3_bucket_policy.backup`), completely removing the need to modify or attach policies to the preexisting IAM role.
* **Least-Privilege Actions**:
  - Object write: `s3:PutObject`, `s3:AbortMultipartUpload` on `${bucket.arn}/*`.
  - Bucket read/multipart: `s3:ListBucket`, `s3:GetBucketLocation`, `s3:ListBucketMultipartUploads` on `${bucket.arn}`.
* **No Destructive Rights**: The role is **not** granted `s3:DeleteObject`, `s3:DeleteBucket`, or administrative permissions.

### B. Customer-Managed KMS Key (CMK) & Envelope Encryption
* **Customer-Managed Key**: Uses a dedicated KMS key (`aws_kms_key.backup`) with automatic annual key rotation enabled (`enable_key_rotation = true`).
* **Root Delegation**: Enables the account root principal (`arn:aws:iam::<account_id>:root`) to administer the key, with an explicit key policy grant for `var.uploader_role_arn` via `s3.${region}.amazonaws.com`.
* **S3 Bucket Key (`bucket_key_enabled = true`)**: Caches a bucket-level key, reducing KMS request traffic and per-request API costs by **up to 99%**.

### C. Zero Public Exposure
* Full Public Access Block (`aws_s3_bucket_public_access_block.backup`) with all 4 protections enabled:
  - `block_public_acls = true`
  - `block_public_policy = true`
  - `ignore_public_acls = true`
  - `restrict_public_buckets = true`

### D. Enforce Secure In-Transit Transport
The bucket policy actively enforces defense-in-depth:
* **Deny Insecure Transport**: Rejects any non-HTTPS requests (`aws:SecureTransport = false`).
* **Deny Deprecated TLS**: Enforces TLS version 1.2 or higher (`s3:TlsVersion < 1.2`), rejecting outdated ciphers.

### E. Ransomware & Accidental Deletion Protection
* S3 Versioning is enabled to protect backups from ransomware overwriting or accidental deletions.
* Lifecycle policies apply identical expiration rules to noncurrent versions, preventing storage retention leaks.

---

## 4. Cost Optimization Strategy

### A. 30 Days Standard Straight into Glacier Deep Archive

Filesystem backups remain in high-performance S3 Standard for **30 days** (the standard operational recovery window), after which they move directly into **S3 Glacier Deep Archive** (the lowest-cost storage tier in AWS):

| Timeframe | Storage Tier | Details & Pricing (eu-west-1) |
| :--- | :--- | :--- |
| **Day 0 – 30** | **S3 Standard** | High performance for operational restores ($0.0230 / GB / mo). |
| **Day 30 – 180** | **S3 Glacier Deep Archive** | Lowest cost archive tier in AWS ($0.00099 / GB / mo — **~95.7% cheaper** than Standard). |
| **Day 180** | **Permanent Expiration** | Enforces *"stores backups for 180 days and no more"*. |

#### Cost Comparison Example (10 TB Backup Volume over 180 days)
* **Without Lifecycle (S3 Standard only for 180 days / 6 months)**:
  $$10{,}000\text{ GB} \times \$0.023 \times 6\text{ months} = \mathbf{\$1{,}380.00}$$
* **With 30-Day Direct-to-Glacier Deep Archive Policy**:
  - Days 0–30 (Month 1 in S3 Standard): $10{,}000 \times \$0.023 = \$230.00$
  - Days 30–180 (Months 2–6 in Glacier Deep Archive): $10{,}000 \times \$0.00099 \times 6\text{ mo (incl. min charge)} = \$59.40$
  - **Total**: $\mathbf{\$289.40}$ (**79.0% direct cost reduction**)

### B. Configurable Lifecycle Parameters

The lifecycle behavior is fully configurable via variables:
- `transition_glacier_days` (default `30`): Number of days in Standard before moving straight to Glacier.
- `glacier_storage_class` (default `"DEEP_ARCHIVE"`): Can be set to `"DEEP_ARCHIVE"`, `"GLACIER"` (Flexible Retrieval), or `"GLACIER_IR"` (Instant Retrieval).
- `transition_ia_days` (default `null`): Optional intermediate Standard-IA tier if desired.

### C. Multipart Upload Cost Leak Prevention
* Filesystem backup archives often span multiple gigabytes and use multipart uploads.
* The rule `abort_incomplete_multipart_upload` deletes incomplete uploads after **7 days**, preventing phantom storage costs.

### D. Expired Delete Marker Cleanup
* A dedicated lifecycle rule removes expired object delete markers when objects are deleted.

---

## 5. File Structure

```
certara_cloud_engineer_feladat/2/
├── versions.tf                 # Terraform >= 1.5.0 & AWS provider >= 5.0 constraints
├── variables.tf                # Parameterized configuration with input validation
├── main.tf                     # S3 bucket, Bucket policy, KMS key, and lifecycle rules
├── outputs.tf                  # Exported bucket ARN, KMS key ARN, and lifecycle summary
├── terraform.tfvars.example    # Example deployment variable values
├── README.md                   # Complete architectural, security, and cost documentation
├── validate.ps1                # PowerShell validation script
└── validate.sh                 # Bash validation script
```

---

## 6. Deployment Guide

### Prerequisites
- [Terraform](https://developer.hashicorp.com/terraform/downloads) v1.5.0 or later installed.
- AWS credentials configured for the target account.

### Step 1: Configure Variables
```bash
cd certara_cloud_engineer_feladat/2
cp terraform.tfvars.example terraform.tfvars
```

Review `terraform.tfvars`:
```hcl
aws_region              = "eu-west-1"
environment             = "prod"
bucket_prefix           = "app-backups-archive-"
uploader_role_arn       = "arn:aws:iam::123456789012:role/backup_uploader"
retention_days          = 180
transition_glacier_days = 30             # 30 days in S3 Standard
glacier_storage_class   = "DEEP_ARCHIVE" # Cheapest Glacier tier
```

### Step 2: Validate and Plan
```bash
terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
```

### Step 3: Apply
```bash
terraform apply tfplan
```
