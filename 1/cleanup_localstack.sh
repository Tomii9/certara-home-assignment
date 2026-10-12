#!/usr/bin/env bash
# ==============================================================================
# Teardown & Cleanup Script for Certara VPC Module (Linux/macOS)
# Destroys Terraform resources in LocalStack and stops the container
# ==============================================================================

set -euo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    RESET=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLE_DIR="${SCRIPT_DIR}/examples/complete"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
REGION="eu-central-1"
PURGE=false
DOWN_ONLY=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Clean up resources created by the Certara VPC LocalStack tests.

Options:
    -h, --help      Show this help message and exit
    -p, --purge     Also remove .terraform cache, lockfiles, and state files
    --down-only     Only stop and remove the LocalStack Docker container
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -p|--purge)
            PURGE=true
            shift
            ;;
        --down-only)
            DOWN_ONLY=true
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
echo -e "${CYAN}  Certara VPC Module - LocalStack Cleanup / Teardown         ${RESET}"
echo -e "${CYAN}============================================================${RESET}"

if [ "$DOWN_ONLY" = false ]; then
    if [ -d "${EXAMPLE_DIR}" ] && command -v terraform >/dev/null 2>&1; then
        echo -e "\n${YELLOW}[1/3] Destroying Terraform resources in ${EXAMPLE_DIR}...${RESET}"
        (
            cd "${EXAMPLE_DIR}"
            export AWS_ACCESS_KEY_ID="test"
            export AWS_SECRET_ACCESS_KEY="test"
            export AWS_DEFAULT_REGION="${REGION}"
            terraform destroy -auto-approve -input=false || true
        )
        echo -e "${GREEN}Terraform destroy completed.${RESET}"
    else
        echo -e "\n${YELLOW}[1/3] Skipping terraform destroy.${RESET}"
    fi
fi

echo -e "\n${YELLOW}[2/3] Stopping LocalStack container...${RESET}"
if command -v docker >/dev/null 2>&1 && [ -f "${COMPOSE_FILE}" ]; then
    docker compose -f "${COMPOSE_FILE}" down || true
    echo -e "${GREEN}LocalStack container stopped and removed.${RESET}"
else
    echo -e "${YELLOW}Docker not available; skipping container shutdown.${RESET}"
fi

if [ "$PURGE" = true ]; then
    echo -e "\n${YELLOW}[3/3] Purging temporary Terraform state and cache files...${RESET}"
    find "${SCRIPT_DIR}" -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
    find "${SCRIPT_DIR}" -type f -name "terraform.tfstate*" -delete 2>/dev/null || true
    find "${SCRIPT_DIR}" -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
    rm -rf "${SCRIPT_DIR}/.localstack" 2>/dev/null || true
    echo -e "${GREEN}Purge completed.${RESET}"
else
    echo -e "\n${YELLOW}[3/3] State cache retained. Use --purge to remove Terraform state files.${RESET}"
fi

echo -e "\n${GREEN}Cleanup finished successfully!${RESET}"
