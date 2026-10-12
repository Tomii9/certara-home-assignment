<#
.SYNOPSIS
    Teardown and cleanup script for Certara VPC Module (PowerShell).
.DESCRIPTION
    Destroys Terraform resources in LocalStack and stops the LocalStack container.
.PARAMETER Purge
    Removes temporary .terraform directories, lockfiles, and state files.
.PARAMETER DownOnly
    Only stops and removes the LocalStack container.
#>

[CmdletBinding()]
param(
    [switch]$Purge,
    [switch]$DownOnly
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Certara VPC Module - LocalStack Cleanup / Teardown         " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exampleDir = Join-Path $scriptDir "examples\complete"
$composeFile = Join-Path $scriptDir "docker-compose.yml"

if (-not $DownOnly) {
    if ((Test-Path $exampleDir) -and (Get-Command terraform -ErrorAction SilentlyContinue)) {
        Write-Host "`n[1/3] Destroying Terraform resources in $exampleDir..." -ForegroundColor Yellow
        Push-Location $exampleDir
        try {
            $env:AWS_ACCESS_KEY_ID = "test"
            $env:AWS_SECRET_ACCESS_KEY = "test"
            $env:AWS_DEFAULT_REGION = "eu-central-1"
            terraform destroy -auto-approve -input=false
            Write-Host "Terraform destroy completed." -ForegroundColor Green
        } catch {
            Write-Warning "Terraform destroy encountered an issue: $_"
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "`n[1/3] Skipping terraform destroy." -ForegroundColor Yellow
    }
}

Write-Host "`n[2/3] Stopping LocalStack container..." -ForegroundColor Yellow
if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path $composeFile)) {
    docker compose -f $composeFile down
    Write-Host "LocalStack container stopped and removed." -ForegroundColor Green
} else {
    Write-Host "Docker not available; skipping container shutdown." -ForegroundColor Yellow
}

if ($Purge) {
    Write-Host "`n[3/3] Purging temporary Terraform state and cache files..." -ForegroundColor Yellow
    Get-ChildItem -Path $scriptDir -Recurse -Directory -Filter ".terraform" -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force
    Get-ChildItem -Path $scriptDir -Recurse -File -Filter "terraform.tfstate*" -Force -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -Path $scriptDir -Recurse -File -Filter ".terraform.lock.hcl" -Force -ErrorAction SilentlyContinue | Remove-Item -Force
    $localstackDir = Join-Path $scriptDir ".localstack"
    if (Test-Path $localstackDir) { Remove-Item -Recurse -Force $localstackDir }
    Write-Host "Purge completed." -ForegroundColor Green
} else {
    Write-Host "`n[3/3] State cache retained. Use -Purge to remove Terraform state files." -ForegroundColor Yellow
}

Write-Host "`nCleanup finished successfully!" -ForegroundColor Green
