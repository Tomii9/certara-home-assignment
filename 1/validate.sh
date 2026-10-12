#!/usr/bin/env bash
# ==============================================================================
# Fast Static Validation Test Script for Certara VPC Module (Linux/macOS)
# Checks code formatting, module syntax, and provider configurations
# Does NOT require Docker or LocalStack to run.
# ==============================================================================

set -euo pipefail

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    RED='\033[0;31m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    CYAN=''
    GREEN=''
    YELLOW=''
    RED=''
    BOLD=''
    RESET=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULE_DIR="${SCRIPT_DIR}/modules/vpc"
EXAMPLE_DIR="${SCRIPT_DIR}/examples/complete"

echo -e "${CYAN}============================================================${RESET}"
echo -e "${CYAN}  Certara VPC Module - Static Validation & Lint Tests       ${RESET}"
echo -e "${CYAN}============================================================${RESET}"

if ! command -v terraform >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] 'terraform' command not found in PATH.${RESET}" >&2
    exit 1
fi

echo -e "${YELLOW}Terraform Version:${RESET} $(terraform version | head -n 1)"

echo -e "\n${YELLOW}[Check 1/3] Checking Terraform code formatting...${RESET}"
if terraform -chdir="${SCRIPT_DIR}" fmt -check -recursive; then
    echo -e "${GREEN}[PASSED] All Terraform files are properly formatted.${RESET}"
else
    echo -e "${RED}[FAILED] Some files require formatting. Run 'terraform fmt -recursive' to fix.${RESET}" >&2
    exit 1
fi

echo -e "\n${YELLOW}[Check 2/3] Validating core VPC module (modules/vpc)...${RESET}"
(
    cd "${MODULE_DIR}"
    terraform init -backend=false -input=false >/dev/null
    terraform validate
)
echo -e "${GREEN}[PASSED] Core VPC module syntax is valid.${RESET}"

echo -e "\n${YELLOW}[Check 3/3] Validating complete example (examples/complete)...${RESET}"
(
    cd "${EXAMPLE_DIR}"
    terraform init -backend=false -input=false >/dev/null
    terraform validate
)
echo -e "${GREEN}[PASSED] Complete example configuration is valid.${RESET}"

if command -v tflint >/dev/null 2>&1; then
    echo -e "\n${YELLOW}[Optional] Running TFLint...${RESET}"
    (
        cd "${MODULE_DIR}"
        tflint --init >/dev/null 2>&1 || true
        tflint
    )
    echo -e "${GREEN}[PASSED] TFLint checks passed.${RESET}"
fi

echo -e "\n${GREEN}============================================================${RESET}"
echo -e "${GREEN}  ALL STATIC VALIDATION TESTS PASSED SUCCESSFULLY!          ${RESET}"
echo -e "${GREEN}============================================================${RESET}"
