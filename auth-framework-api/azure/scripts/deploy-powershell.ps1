<#
.SYNOPSIS
    Deploy Auth Framework to Azure using PowerShell.

.DESCRIPTION
    Full Azure deployment script for Auth Framework (.NET 9 / PostgreSQL).
    Handles Docker build/push, Terraform infrastructure, and database migrations.

.PARAMETER Environment
    Target environment: dev, staging, or prod

.PARAMETER Subscription
    Azure subscription ID

.PARAMETER ResourceGroup
    Azure resource group name

.PARAMETER AcrName
    Azure Container Registry name

.PARAMETER Location
    Azure region (default: eastus2)

.PARAMETER SkipDocker
    Skip Docker build and push

.PARAMETER SkipTerraform
    Skip Terraform infrastructure deployment

.PARAMETER SkipMigrations
    Skip database migrations

.EXAMPLE
    .\deploy-powershell.ps1 -Environment dev -Subscription "00000000-..." -ResourceGroup rg-authframework-dev -AcrName myacr
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$Subscription,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$AcrName,

    [string]$Location = "eastus2",

    [switch]$SkipDocker,
    [switch]$SkipTerraform,
    [switch]$SkipMigrations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $ScriptDir))
$TerraformDir = Join-Path $RepoRoot "auth-framework-api\azure\terraform"
$ApiDir = Join-Path $RepoRoot "auth-framework-api"

function Write-Log {
    param([string]$Level, [string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "OK"      { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        default   { "White" }
    }
    Write-Host "[$Level]  $timestamp $Message" -ForegroundColor $color
}

function Test-RequiredTool {
    param([string]$Tool)
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        Write-Log "ERROR" "Required tool not found: $Tool"
        exit 1
    }
}

# Check required tools
Test-RequiredTool "az"
if (-not $SkipDocker)     { Test-RequiredTool "docker" }
if (-not $SkipTerraform)  { Test-RequiredTool "terraform" }
if (-not $SkipMigrations) { Test-RequiredTool "dotnet" }

# Validate secrets
$requiredEnvVars = @("DB_PASSWORD", "JWT_SECRET_KEY", "ENCRYPTION_KEY")
foreach ($varName in $requiredEnvVars) {
    if (-not [System.Environment]::GetEnvironmentVariable($varName)) {
        Write-Log "ERROR" "Required environment variable not set: $varName"
        exit 1
    }
}

$ImageTag = if ($env:IMAGE_TAG) { $env:IMAGE_TAG } else { "$(Get-Date -Format 'yyyyMMdd')-$Environment" }
$AcrLoginServer = "$AcrName.azurecr.io"
$ImageName = "authframework-api"

Write-Log "INFO" "Starting deployment: $Environment"
Write-Log "INFO" "  Subscription:   $Subscription"
Write-Log "INFO" "  Resource Group: $ResourceGroup"
Write-Log "INFO" "  ACR:            $AcrLoginServer"
Write-Log "INFO" "  Image tag:      $ImageTag"

# Azure login verification
Write-Log "INFO" "Setting Azure subscription..."
az account set --subscription $Subscription
if ($LASTEXITCODE -ne 0) { Write-Log "ERROR" "Failed to set subscription"; exit 1 }
Write-Log "OK" "Subscription set"

# Terraform
if (-not $SkipTerraform) {
    Write-Log "INFO" "====== Terraform Infrastructure ======"
    Push-Location $TerraformDir
    try {
        terraform init
        if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

        terraform plan -out=tfplan `
            -var="environment=$Environment" `
            -var="project_name=authframework" `
            -var="location=$Location" `
            -var="db_password=$($env:DB_PASSWORD)" `
            -var="jwt_secret_key=$($env:JWT_SECRET_KEY)" `
            -var="encryption_key=$($env:ENCRYPTION_KEY)"
        if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }

        terraform apply -auto-approve tfplan
        if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }

        Write-Log "OK" "Terraform apply complete"
    }
    finally {
        Pop-Location
    }
}

# Docker build and push
if (-not $SkipDocker) {
    Write-Log "INFO" "====== Docker Build and Push ======"
    az acr login --name $AcrName
    if ($LASTEXITCODE -ne 0) { Write-Log "ERROR" "ACR login failed"; exit 1 }

    $fullImageTag = "$AcrLoginServer/${ImageName}:${ImageTag}"
    $latestTag    = "$AcrLoginServer/${ImageName}:latest"
    $dockerfile   = Join-Path $ApiDir "Dockerfile"

    docker build --platform linux/amd64 `
        -t $fullImageTag `
        -t $latestTag `
        -f $dockerfile `
        "$ApiDir/"
    if ($LASTEXITCODE -ne 0) { Write-Log "ERROR" "Docker build failed"; exit 1 }

    docker push $fullImageTag
    docker push $latestTag
    if ($LASTEXITCODE -ne 0) { Write-Log "ERROR" "Docker push failed"; exit 1 }
    Write-Log "OK" "Image pushed: $fullImageTag"
}

# Migrations
if (-not $SkipMigrations) {
    Write-Log "INFO" "====== Database Migrations ======"
    dotnet tool install --global dotnet-ef --ignore-failed-sources 2>$null
    $infraProject = Join-Path $ApiDir "src\AuthFramework.Infrastructure"
    $apiProject   = Join-Path $ApiDir "src\AuthFramework.Api\AuthFramework.Api.csproj"

    Push-Location $infraProject
    try {
        dotnet ef database update --startup-project $apiProject
        if ($LASTEXITCODE -ne 0) { throw "Migration failed" }
        Write-Log "OK" "Migrations applied"
    }
    finally {
        Pop-Location
    }
}

# Health check
Write-Log "INFO" "====== Health Check ======"
$appName = "authframework-$Environment-api"
$appUrl = "https://$appName.azurewebsites.net"

az webapp restart --name $appName --resource-group $ResourceGroup --output none

for ($i = 1; $i -le 12; $i++) {
    try {
        $response = Invoke-WebRequest -Uri "$appUrl/health" -TimeoutSec 15 -UseBasicParsing -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Log "OK" "Health check passed (HTTP 200)"
            break
        }
    } catch {
        Write-Log "WARN" "Attempt $i/12: Not ready yet, waiting 15s..."
        Start-Sleep -Seconds 15
    }
}

Write-Log "OK" "====== Deployment Complete ======"
Write-Log "OK" "Application URL: $appUrl"
