# ==============================================================================
# Static Validation Script for Task 2: S3 Backup Module (PowerShell)
# Checks code formatting and Terraform syntax without requiring cloud credentials
# ==============================================================================

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Task 2: S3 Backup Bucket - Static Validation & Syntax Test" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] 'terraform' command not found in PATH." -ForegroundColor Red
    exit 1
}

$tfVer = (terraform version | Select-Object -First 1)
Write-Host "Terraform Version: $tfVer" -ForegroundColor Yellow

Write-Host "`n[Check 1/2] Checking Terraform code formatting..." -ForegroundColor Yellow
$fmtResult = terraform fmt -check $PSScriptRoot
if ($LASTEXITCODE -eq 0) {
    Write-Host "[PASSED] All Terraform files are properly formatted." -ForegroundColor Green
} else {
    Write-Host "[FAILED] Formatting check failed. Run 'terraform fmt' to fix." -ForegroundColor Red
    exit 1
}

Write-Host "`n[Check 2/2] Validating Terraform configuration..." -ForegroundColor Yellow
Push-Location $PSScriptRoot
try {
    terraform init -backend=false -input=false | Out-Null
    $validateOutput = terraform validate
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[PASSED] $validateOutput" -ForegroundColor Green
    } else {
        Write-Host "[FAILED] Terraform validation failed." -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  ALL TASK 2 VALIDATION CHECKS PASSED SUCCESSFULLY!         " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
