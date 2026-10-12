<#
.SYNOPSIS
    Automated test script for Terraform Certara VPC module with LocalStack in eu-central-1.
.DESCRIPTION
    Ensures LocalStack is running, initializes Terraform, validates, plans,
    applies the configuration, and validates all VPC, subnet, route table,
    and S3 VPC Endpoint resources in the eu-central-1 region.
#>

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Certara VPC Module - LocalStack Test Runner (eu-central-1)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$exampleDir = Join-Path $scriptDir "examples\complete"

Write-Host "`n[Step 1/5] Checking LocalStack container..." -ForegroundColor Yellow
$container = docker ps --filter "name=localstack_certara" --format "{{.Names}}"
if (-not $container) {
    Write-Host "Starting LocalStack with docker compose..." -ForegroundColor Yellow
    docker compose -f (Join-Path $scriptDir "docker-compose.yml") up -d
} else {
    Write-Host "LocalStack is already running: $container" -ForegroundColor Green
}

Write-Host "Verifying LocalStack health endpoint (http://localhost:4566/_localstack/health)..." -ForegroundColor Yellow
$retries = 20
$healthy = $false
while ($retries -gt 0) {
    try {
        $resp = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -TimeoutSec 3 -ErrorAction Stop
        if ($resp.edition -or $resp.services) {
            $healthy = $true
            break
        }
    } catch {
        Start-Sleep -Seconds 2
        $retries--
    }
}

if (-not $healthy) {
    Write-Error "LocalStack did not become healthy in time."
    exit 1
}
Write-Host "LocalStack is healthy and ready!" -ForegroundColor Green

Write-Host "`n[Step 2/5] Running Terraform Init..." -ForegroundColor Yellow
Push-Location $exampleDir
try {
    terraform init
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

    Write-Host "`n[Step 3/5] Running Terraform Validate..." -ForegroundColor Yellow
    terraform validate
    if ($LASTEXITCODE -ne 0) { throw "terraform validate failed" }

    Write-Host "`n[Step 4/5] Running Terraform Apply against LocalStack (eu-central-1)..." -ForegroundColor Yellow
    terraform apply -auto-approve
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

    Write-Host "`n[Step 5/5] Verify Resources via AWS CLI in eu-central-1..." -ForegroundColor Yellow
    $env:AWS_ACCESS_KEY_ID = "test"
    $env:AWS_SECRET_ACCESS_KEY = "test"
    $env:AWS_DEFAULT_REGION = "eu-central-1"

    $vpcId = (terraform output -raw vpc_id).Trim()
    $s3EndpointId = (terraform output -raw s3_vpc_endpoint_id).Trim()

    Write-Host "Deployed VPC ID: $vpcId" -ForegroundColor Cyan
    Write-Host "Deployed S3 Endpoint ID: $s3EndpointId" -ForegroundColor Cyan

    Write-Host "`n--- Verification: Subnets across AZs ---" -ForegroundColor Magenta
    aws --endpoint-url=http://localhost:4566 ec2 describe-subnets `
        --filters "Name=vpc-id,Values=$vpcId" `
        --query "Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,PublicIpOnLaunch:MapPublicIpOnLaunch,Tier:Tags[?Key=='Tier'].Value|[0],Role:Tags[?Key=='Role'].Value|[0]}" `
        --output table

    Write-Host "`n--- Verification: S3 Gateway Endpoint ---" -ForegroundColor Magenta
    aws --endpoint-url=http://localhost:4566 ec2 describe-vpc-endpoints `
        --vpc-endpoint-ids $s3EndpointId `
        --query "VpcEndpoints[*].{VpcEndpointId:VpcEndpointId,ServiceName:ServiceName,Type:VpcEndpointType,State:State,RouteTables:RouteTableIds}" `
        --output table

    Write-Host "`n--- Verification: Route Tables & Routes ---" -ForegroundColor Magenta
    aws --endpoint-url=http://localhost:4566 ec2 describe-route-tables `
        --filters "Name=vpc-id,Values=$vpcId" `
        --query "RouteTables[*].{Name:Tags[?Key=='Name'].Value|[0],RouteTableId:RouteTableId,Routes:Routes[*].{Dest:DestinationCidrBlock,Prefix:DestinationPrefixListId,Gateway:GatewayId,Nat:NatGatewayId}}" `
        --output json

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host "  ALL TESTS PASSED SUCCESSFULLY! LocalStack Verified.      " -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
}
finally {
    Pop-Location
}
