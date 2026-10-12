# AWS VPC Terraform Module (eu-central-1)

This repository provides an enterprise-ready, production-grade Terraform module for deploying a secure, multi-AZ AWS Virtual Private Cloud (VPC) in the `eu-central-1` (Frankfurt) region, featuring segregated public and private tiers, outbound internet access, and a private S3 Gateway VPC Endpoint.

> **Design Principle**: The core module (`modules/vpc`) contains **zero LocalStack code** and is 100% pure, cloud-agnostic AWS Terraform. LocalStack test configurations and mocks are isolated strictly within the example (`examples/complete`) and accompanying test scripts.


### Key Architectural Characteristics

1. **VPC with Internet Access**:
   - Deploys an `aws_vpc` with configurable CIDR (default: `10.0.0.0/16`) and DNS hostnames/support enabled.
   - Deploys an `aws_internet_gateway` attached to the VPC.

2. **4 Subnets across 2 Availability Zones (`eu-central-1a` & `eu-central-1b`)**:
   - Automatically distributes subnets across 2 AZs.
   - **2 Public Subnets** (`10.0.1.0/24`, `10.0.2.0/24`):
     - Designed to host Load Balancers (ALB/NLB) or Reverse Proxies (NGINX/Envoy).
     - Direct two-way communication with the public internet via the Internet Gateway (`0.0.0.0/0` -> `igw`).
     - `map_public_ip_on_launch = true`.
   - **2 Private Subnets** (`10.0.10.0/24`, `10.0.11.0/24`):
     - Designed to host backend Application Servers and internal services.
     - Protected from unsolicited incoming internet connections (`map_public_ip_on_launch = false`).
     - Egress outbound internet communication through an `aws_nat_gateway` placed in a public subnet.

3. **S3 Gateway VPC Endpoint (Security & Cost Reduction)**:
   - Provisions an `aws_vpc_endpoint` of type `Gateway` targeting `com.amazonaws.eu-central-1.s3`.
   - Automatically updates both the public and private route tables with prefix-list routes pointing directly to the gateway endpoint.
   - **Security**: Traffic from within the VPC never traverses the public internet or external proxies. All API calls stay securely on the private AWS network backbone.
   - **Cost Reduction**: Gateway endpoints are free of charge (no hourly endpoint fees), and routing S3 requests through the gateway endpoint bypasses NAT Gateway data transfer and data processing fees ($0.045/GB saved).

---

## Directory Structure

```
certara_cloud_engineer_feladat/
├── .gitignore               # Root gitignore for Terraform & artifacts
└── 1/
    ├── modules/
    │   └── vpc/             # Pure AWS Terraform module
    │       ├── main.tf      # Core VPC, Subnets, Gateways, Route Tables, and S3 Endpoint
    │       ├── variables.tf # Configurable variables with validation rules
    │       ├── outputs.tf   # Exported resource IDs, CIDRs, and ARNs
    │       └── versions.tf  # Provider requirements (AWS >= 5.0, Terraform >= 1.5)
    ├── examples/
    │   └── complete/        # Example consuming the module
    │       ├── main.tf      # Module call, example S3 bucket & Security Groups
    │       ├── variables.tf # Region default eu-central-1 and localstack_endpoint
    │       ├── outputs.tf   # Example outputs
    │       └── versions.tf  # AWS provider (configured for LocalStack testing)
    ├── docker-compose.yml   # LocalStack v4.4.0 service definition
    ├── Makefile             # Automation targets for Linux/macOS (test, validate, clean)
    ├── test_localstack.sh   # Automated Bash test runner with assertions (Linux/macOS)
    ├── test_localstack.ps1  # Automated PowerShell test runner for LocalStack (Windows)
    ├── validate.sh          # Fast static validation & fmt test runner (no Docker needed)
    ├── cleanup_localstack.sh   # Teardown & cleanup script (Linux/macOS)
    ├── cleanup_localstack.ps1  # Teardown & cleanup script (Windows)
    └── README.md            # Documentation and architecture guide
```

---

## Module Reference (`modules/vpc`)

### Inputs

| Name | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `name` | `string` | `"certara-vpc"` | Identifier prefix applied to all resources |
| `vpc_cidr` | `string` | `"10.0.0.0/16"` | IPv4 CIDR block for the VPC |
| `enable_dns_hostnames` | `bool` | `true` | Enable DNS hostnames in the VPC |
| `enable_dns_support` | `bool` | `true` | Enable DNS support in the VPC |
| `availability_zones` | `list(string)` | `null` | Exactly 2 AZs (auto-detected if `null`) |
| `public_subnet_cidrs` | `list(string)` | `["10.0.1.0/24", "10.0.2.0/24"]` | CIDR blocks for the 2 public subnets |
| `private_subnet_cidrs` | `list(string)` | `["10.0.10.0/24", "10.0.11.0/24"]` | CIDR blocks for the 2 private subnets |
| `enable_nat_gateway` | `bool` | `true` | Provision NAT Gateway for private egress |
| `single_nat_gateway` | `bool` | `true` | Use a single shared NAT Gateway (cost-effective) or one per AZ |
| `enable_s3_endpoint` | `bool` | `true` | Provision Gateway VPC Endpoint for Amazon S3 |
| `tags` | `map(string)` | `{}` | Tags to merge onto all resources |

### Outputs

| Name | Description |
| :--- | :--- |
| `vpc_id` | ID of the VPC |
| `vpc_arn` | ARN of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `public_subnet_ids` | IDs of the 2 public subnets |
| `private_subnet_ids` | IDs of the 2 private subnets |
| `internet_gateway_id` | ID of the Internet Gateway |
| `nat_gateway_ids` | IDs of the deployed NAT Gateway(s) |
| `nat_public_ips` | Elastic IP(s) allocated for the NAT Gateway(s) |
| `s3_vpc_endpoint_id` | ID of the S3 Gateway VPC Endpoint |
| `s3_vpc_endpoint_prefix_list_id` | Prefix list ID of the S3 VPC Endpoint |
| `public_route_table_id` | ID of the public route table |
| `private_route_table_ids` | IDs of the private route table(s) |
| `availability_zones` | List of the 2 availability zones used |

---

## Example Usage

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name                 = "my-production-vpc"
  vpc_cidr             = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  # 4 subnets across 2 AZs in eu-central-1
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.11.0/24"]

  # NAT Gateway for private outbound connections
  enable_nat_gateway   = true
  single_nat_gateway   = true

  # Keep S3 API traffic inside AWS backbone
  enable_s3_endpoint   = true

  tags = {
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
```

---

## Automated Testing & Validation

### Option A: Linux / macOS / Bash

#### 1. Fast Static Validation (No Docker needed)
```bash
./validate.sh
# or using Makefile:
make validate
```
Validates canonical code formatting (`terraform fmt -check`), module syntax, and complete example configuration in seconds without requiring LocalStack or AWS credentials.

#### 2. End-to-End Test with LocalStack
```bash
./test_localstack.sh
# or using Makefile:
make test

# To auto-destroy resources after passing:
./test_localstack.sh --auto-destroy
# or:
make test-auto-destroy
```

#### 3. Teardown / Cleanup
```bash
./cleanup_localstack.sh
# or purge state and caches:
./cleanup_localstack.sh --purge
# or using Makefile:
make clean
```

---

### Option B: Windows PowerShell

#### 1. Start LocalStack
```powershell
docker compose up -d
```

#### 2. Run Automated Tests
```powershell
powershell -ExecutionPolicy Bypass -File .\test_localstack.ps1
```

#### 3. Teardown / Cleanup
```powershell
powershell -ExecutionPolicy Bypass -File .\cleanup_localstack.ps1 -Purge
```

---

### What the Automated Test Suite Verifies:
1. **Container Health**: LocalStack running and responsive at `http://localhost:4566/_localstack/health`.
2. **Terraform Lifecycle**: Clean `terraform init`, `terraform validate`, and `terraform apply` against `eu-central-1`.
3. **Automated Assertions & AWS CLI Verifications**:
   - VPC created with matching CIDR and DNS attributes.
   - **4 subnets** verified across **2 AZs** (`eu-central-1a` & `eu-central-1b`).
   - Strict subnet tier isolation: **2 public subnets** (`map_public_ip_on_launch = true`) and **2 private subnets** (`map_public_ip_on_launch = false`).
   - **S3 Gateway VPC Endpoint** created, active in `available` state, and prefix-list routes populated in route tables.
   - NAT Gateway and Internet Gateway routes properly associated.
