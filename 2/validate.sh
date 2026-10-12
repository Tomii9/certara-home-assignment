#!/usr/bin/env bash
# ==============================================================================
# Static Validation Script for Task 2: S3 Backup Module (Linux/macOS)
# Checks code formatting and Terraform syntax without requiring cloud credentials
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

echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN}  Task 2: S3 Backup Bucket - Static Validation & Syntax Test${RESET}"
echo -e "${CYAN}============================================================${RESET}"

if ! command -v terraform >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 'terraform' command not found in PATH.${RESET}" >&2
    exit 1
fi

echo -e "${YELLOW}Terraform Version:${RESET} $(terraform version | head -n 1)"

echo -e "\n${YELLOW}[Check 1/2] Checking Terraform code formatting...${RESET}"
if terraform -chdir="${SCRIPT_DIR}" fmt -check; then
    echo -e "${GREEN}[PASSED] All Terraform files are properly formatted.${RESET}"
else
    echo -e "${RED}[FAILED] Some files require formatting. Run 'terraform fmt' to fix.${RESET}" >&2
    exit 1
fi

echo -e "\n${YELLOW}[Check 2/2] Validating Terraform configuration...${RESET}"
(
    cd "${SCRIPT_DIR}"
    terraform init -backend=false -input=false >/dev/null
    terraform validate
)
echo -e "${GREEN}[PASSED] Terraform validation succeeded.${RESET}"

echo -e "\n${GREEN}============================================================${RESET}"
echo -e "${GREEN}  ALL TASK 2 VALIDATION CHECKS PASSED SUCCESSFULLY!         ${RESET}"
echo -e "${GREEN}============================================================${RESET}"
