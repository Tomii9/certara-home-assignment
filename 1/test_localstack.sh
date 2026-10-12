#!/usr/bin/env bash
# ==============================================================================
# Automated Test Runner for Certara VPC Terraform Module on LocalStack (Linux/macOS)
# Target Region: eu-central-1 (Frankfurt)
# ==============================================================================

set -euo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    MAGENTA=''
    BOLD=''
    RESET=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="${SCRIPT_DIR}/examples/complete"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
CONTAINER_NAME="localstack_certara"
HEALTH_URL="http://localhost:4566/_localstack/health"
ENDPOINT_URL="http://localhost:4566"
REGION="eu-central-1"

AUTO_DESTROY=false
DESTROY_ONLY=false
SKIP_DOCKER=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automated test runner for Certara AWS VPC Terraform module against LocalStack.

Options:
    -h, --help            Show this help message and exit
    -a, --auto-destroy    Automatically destroy Terraform resources on test completion
    -d, --destroy-only    Destroy existing Terraform resources and exit
    --skip-docker         Skip starting Docker container (if LocalStack is already managed)

Requirements:
    - docker and docker compose
    - terraform (>= 1.5.0)
    - aws cli
    - curl
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -a|--auto-destroy)
            AUTO_DESTROY=true
            shift
            ;;
        -d|--destroy-only)
            DESTROY_ONLY=true
            shift
            ;;
        --skip-docker)
            SKIP_DOCKER=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}" >&2
            usage
            exit 1
            ;;
    esac
done

echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN}  Certara VPC Module - LocalStack Test Runner (${REGION})  ${RESET}"
echo -e "${CYAN}============================================================${RESET}"

check_command() {
    local cmd="$1"
    local hint="$2"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Required tool '$cmd' is not installed or not in PATH.${RESET}" >&2
        echo -e "${YELLOW}Hint: $hint${RESET}" >&2
        exit 1
    fi
}

echo -e "\n${YELLOW}[Prerequisites] Checking required tools...${RESET}"
check_command "terraform" "Install Terraform: https://developer.hashicorp.com/terraform/install"
check_command "aws" "Install AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
check_command "curl" "Install curl via your package manager"

if [ "$SKIP_DOCKER" = false ]; then
    check_command "docker" "Install Docker: https://docs.docker.com/get-docker/"
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] 'docker compose' plugin is required.${RESET}" >&2
        exit 1
    fi
fi
echo -e "${GREEN}All required tools are available!${RESET}"

if [ "$DESTROY_ONLY" = true ]; then
    echo -e "\n${YELLOW}Running Terraform Destroy in ${EXAMPLE_DIR}...${RESET}"
    cd "${EXAMPLE_DIR}"
    export AWS_ACCESS_KEY_ID="test"
    export AWS_SECRET_ACCESS_KEY="test"
    export AWS_DEFAULT_REGION="${REGION}"
    terraform destroy -auto-approve -input=false
    echo -e "${GREEN}Terraform resources destroyed successfully.${RESET}"
    exit 0
fi

echo -e "\n${YELLOW}[Step 1/5] Checking LocalStack container...${RESET}"
if [ "$SKIP_DOCKER" = false ]; then
    RUNNING_CONTAINER=$(docker ps --filter "name=${CONTAINER_NAME}" --format '{{.Names}}' 2>/dev/null || true)
    if [ -z "${RUNNING_CONTAINER}" ]; then
        echo -e "${YELLOW}Starting LocalStack with docker compose...${RESET}"
        docker compose -f "${COMPOSE_FILE}" up -d
    else
        echo -e "${GREEN}LocalStack is already running: ${RUNNING_CONTAINER}${RESET}"
    fi
fi

echo -e "Verifying LocalStack health endpoint (${HEALTH_URL})..."
MAX_RETRIES=30
RETRY_COUNT=0
HEALTHY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if RESPONSE=$(curl -fsSL --connect-timeout 3 "${HEALTH_URL}" 2>/dev/null); then
        if echo "${RESPONSE}" | grep -q -E '"edition"|"services"|"available"'; then
            HEALTHY=true
            break
        fi
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "Waiting for LocalStack to be ready (attempt ${RETRY_COUNT}/${MAX_RETRIES})..."
    sleep 2
done

if [ "$HEALTHY" = false ]; then
    echo -e "${RED}[ERROR] LocalStack did not become healthy within the timeout period.${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}LocalStack is healthy and ready!${RESET}"

echo -e "\n${YELLOW}[Step 2/5] Running Terraform Init...${RESET}"
cd "${EXAMPLE_DIR}"
terraform init -input=false

echo -e "\n${YELLOW}[Step 3/5] Running Terraform Validate...${RESET}"
terraform validate

echo -e "\n${YELLOW}[Step 4/5] Running Terraform Apply against LocalStack (${REGION})...${RESET}"
terraform apply -auto-approve -input=false

echo -e "\n${YELLOW}[Step 5/5] Verifying Resources via AWS CLI in ${REGION}...${RESET}"
export AWS_ACCESS_KEY_ID="test"
export AWS_SECRET_ACCESS_KEY="test"
export AWS_DEFAULT_REGION="${REGION}"

VPC_ID=$(terraform output -raw vpc_id 2>/dev/null | tr -d '\r\n')
S3_ENDPOINT_ID=$(terraform output -raw s3_vpc_endpoint_id 2>/dev/null | tr -d '\r\n')

if [ -z "${VPC_ID}" ] || [[ ! "${VPC_ID}" =~ ^vpc- ]]; then
    echo -e "${RED}[ASSERTION FAILED] Invalid or missing vpc_id output: '${VPC_ID}'${RESET}" >&2
    exit 1
fi

if [ -z "${S3_ENDPOINT_ID}" ] || [[ ! "${S3_ENDPOINT_ID}" =~ ^vpce- ]]; then
    echo -e "${RED}[ASSERTION FAILED] Invalid or missing s3_vpc_endpoint_id output: '${S3_ENDPOINT_ID}'${RESET}" >&2
    exit 1
fi

echo -e "${CYAN}Deployed VPC ID: ${VPC_ID}${RESET}"
echo -e "${CYAN}Deployed S3 Endpoint ID: ${S3_ENDPOINT_ID}${RESET}"

echo -e "\n${MAGENTA}--- Verification: Subnets across AZs ---${RESET}"
aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,PublicIpOnLaunch:MapPublicIpOnLaunch,Tier:Tags[?Key=='Tier'].Value|[0],Role:Tags[?Key=='Role'].Value|[0]}" \
    --output table

SUBNET_COUNT=$(aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "length(Subnets)" \
    --output text 2>/dev/null | tr -d '\r\n')

if [ "${SUBNET_COUNT}" -ne 4 ]; then
    echo -e "${RED}[ASSERTION FAILED] Expected 4 subnets, found: ${SUBNET_COUNT}${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}[ASSERTION PASSED] Exactly 4 subnets deployed.${RESET}"

PUBLIC_SUBNET_COUNT=$(aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'length(Subnets[?MapPublicIpOnLaunch==`true`])' \
    --output text 2>/dev/null | tr -d '\r\n')

PRIVATE_SUBNET_COUNT=$(aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'length(Subnets[?MapPublicIpOnLaunch==`false`])' \
    --output text 2>/dev/null | tr -d '\r\n')

if [ "${PUBLIC_SUBNET_COUNT}" -ne 2 ] || [ "${PRIVATE_SUBNET_COUNT}" -ne 2 ]; then
    echo -e "${RED}[ASSERTION FAILED] Expected 2 public and 2 private subnets (found ${PUBLIC_SUBNET_COUNT} public, ${PRIVATE_SUBNET_COUNT} private).${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}[ASSERTION PASSED] Segregation verified: 2 public subnets and 2 private subnets.${RESET}"

echo -e "\n${MAGENTA}--- Verification: S3 Gateway Endpoint ---${RESET}"
aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids "${S3_ENDPOINT_ID}" \
    --query "VpcEndpoints[*].{VpcEndpointId:VpcEndpointId,ServiceName:ServiceName,Type:VpcEndpointType,State:State,RouteTables:RouteTableIds}" \
    --output table

ENDPOINT_STATE=$(aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-vpc-endpoints \
    --vpc-endpoint-ids "${S3_ENDPOINT_ID}" \
    --query "VpcEndpoints[0].State" \
    --output text 2>/dev/null | tr -d '\r\n')

if [ "${ENDPOINT_STATE}" != "available" ]; then
    echo -e "${RED}[ASSERTION FAILED] S3 VPC Endpoint state is '${ENDPOINT_STATE}', expected 'available'.${RESET}" >&2
    exit 1
fi
echo -e "${GREEN}[ASSERTION PASSED] S3 Gateway VPC Endpoint is available.${RESET}"

echo -e "\n${MAGENTA}--- Verification: Route Tables & Routes ---${RESET}"
aws --endpoint-url="${ENDPOINT_URL}" ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "RouteTables[*].{Name:Tags[?Key=='Name'].Value|[0],RouteTableId:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Prefix:DestinationPrefixListId,Gateway:GatewayId,Nat:NatGatewayId}}" \
    --output json

if [ "$AUTO_DESTROY" = true ]; then
    echo -e "\n${YELLOW}[Teardown] Auto-destroying Terraform resources (--auto-destroy was set)...${RESET}"
    terraform destroy -auto-approve -input=false
    echo -e "${GREEN}Teardown complete.${RESET}"
fi

echo -e "\n${GREEN}============================================================${RESET}"
echo -e "${GREEN}  ALL TESTS PASSED SUCCESSFULLY! LocalStack Verified.      ${RESET}"
echo -e "${GREEN}============================================================${RESET}"
