#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
TERRAFORM_DIR="${REPO_ROOT}/auth-framework-api/azure/terraform"
API_DIR="${REPO_ROOT}/auth-framework-api"

log_info()    { echo "[INFO]  $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_success() { echo "[OK]    $(date '+%Y-%m-%d %H:%M:%S') $*"; }
log_warn()    { echo "[WARN]  $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_error()   { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }
log_step()    { echo ""; echo "====== $* ======"; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Full Azure deployment of Auth Framework (Docker build + Terraform + Migrations).

OPTIONS:
  -e, --environment      Environment (dev|staging|prod) [required]
  -s, --subscription     Azure subscription ID [required]
  -g, --resource-group   Resource group name [required]
  -r, --acr-name         Azure Container Registry name [required]
  -l, --location         Azure region (default: eastus2)
  --skip-docker          Skip Docker build and push
  --skip-terraform       Skip Terraform infrastructure deploy
  --skip-migrations      Skip database migrations
  --terraform-backend-rg Terraform state storage resource group
  --terraform-backend-sa Terraform state storage account name
  -h, --help             Show this help

REQUIRED ENV VARS:
  DB_PASSWORD, JWT_SECRET_KEY, ENCRYPTION_KEY
EOF
}

ENVIRONMENT=""
SUBSCRIPTION=""
RESOURCE_GROUP=""
ACR_NAME=""
LOCATION="eastus2"
SKIP_DOCKER=false
SKIP_TERRAFORM=false
SKIP_MIGRATIONS=false
TF_BACKEND_RG=""
TF_BACKEND_SA=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -e|--environment)       ENVIRONMENT="$2";      shift 2 ;;
    -s|--subscription)      SUBSCRIPTION="$2";     shift 2 ;;
    -g|--resource-group)    RESOURCE_GROUP="$2";   shift 2 ;;
    -r|--acr-name)          ACR_NAME="$2";         shift 2 ;;
    -l|--location)          LOCATION="$2";         shift 2 ;;
    --skip-docker)          SKIP_DOCKER=true;       shift ;;
    --skip-terraform)       SKIP_TERRAFORM=true;    shift ;;
    --skip-migrations)      SKIP_MIGRATIONS=true;   shift ;;
    --terraform-backend-rg) TF_BACKEND_RG="$2";    shift 2 ;;
    --terraform-backend-sa) TF_BACKEND_SA="$2";    shift 2 ;;
    -h|--help)              usage; exit 0 ;;
    *)                      log_error "Unknown: $1"; usage; exit 1 ;;
  esac
done

[[ -z "$ENVIRONMENT" ]]    && { log_error "--environment is required";    exit 1; }
[[ -z "$SUBSCRIPTION" ]]   && { log_error "--subscription is required";   exit 1; }
[[ -z "$RESOURCE_GROUP" ]] && { log_error "--resource-group is required"; exit 1; }
[[ -z "$ACR_NAME" ]]       && { log_error "--acr-name is required";       exit 1; }

for tool in az docker dotnet; do
  command -v "$tool" &>/dev/null || { log_error "Required tool not found: $tool (install it first)"; exit 1; }
done

[[ -z "${DB_PASSWORD:-}" ]]    && { log_error "DB_PASSWORD env var required"; exit 1; }
[[ -z "${JWT_SECRET_KEY:-}" ]] && { log_error "JWT_SECRET_KEY env var required"; exit 1; }
[[ -z "${ENCRYPTION_KEY:-}" ]] && { log_error "ENCRYPTION_KEY env var required"; exit 1; }

IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d)-${ENVIRONMENT}}"
IMAGE_NAME="authframework-api"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"

log_info "Deployment configuration:"
log_info "  Environment:    $ENVIRONMENT"
log_info "  Subscription:   $SUBSCRIPTION"
log_info "  Resource Group: $RESOURCE_GROUP"
log_info "  ACR:            $ACR_LOGIN_SERVER"
log_info "  Image tag:      $IMAGE_TAG"

# Step 1: Azure login
log_step "Azure Login"
az account set --subscription "$SUBSCRIPTION"
log_success "Subscription set"

# Step 2: Terraform
if [[ "$SKIP_TERRAFORM" == "false" ]]; then
  log_step "Terraform Infrastructure"
  pushd "$TERRAFORM_DIR" > /dev/null

  TF_INIT_ARGS=()
  if [[ -n "$TF_BACKEND_RG" && -n "$TF_BACKEND_SA" ]]; then
    TF_INIT_ARGS+=(
      "-backend-config=resource_group_name=${TF_BACKEND_RG}"
      "-backend-config=storage_account_name=${TF_BACKEND_SA}"
      "-backend-config=container_name=tfstate"
      "-backend-config=key=${ENVIRONMENT}.terraform.tfstate"
    )
  fi

  terraform init "${TF_INIT_ARGS[@]}"
  terraform plan -out=tfplan \
    -var="environment=${ENVIRONMENT}" \
    -var="project_name=authframework" \
    -var="location=${LOCATION}" \
    -var="db_password=${DB_PASSWORD}" \
    -var="jwt_secret_key=${JWT_SECRET_KEY}" \
    -var="encryption_key=${ENCRYPTION_KEY}"
  terraform apply -auto-approve tfplan
  log_success "Terraform apply complete"

  ACR_LOGIN_SERVER=$(terraform output -raw acr_login_server 2>/dev/null || echo "$ACR_LOGIN_SERVER")
  popd > /dev/null
fi

# Step 3: Docker build and push
if [[ "$SKIP_DOCKER" == "false" ]]; then
  log_step "Docker Build and Push"
  log_info "Logging into ACR: $ACR_LOGIN_SERVER"
  az acr login --name "$ACR_NAME"

  log_info "Building Docker image..."
  docker build \
    --platform linux/amd64 \
    -t "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
    -t "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:latest" \
    -f "${API_DIR}/Dockerfile" \
    "${API_DIR}/"

  log_info "Pushing image to ACR..."
  docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
  docker push "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:latest"
  log_success "Docker image pushed: ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}"
fi

# Step 4: Database migrations
if [[ "$SKIP_MIGRATIONS" == "false" ]]; then
  log_step "Database Migrations"
  "${SCRIPT_DIR}/migrate-database.sh" \
    --subscription "$SUBSCRIPTION" \
    --resource-group "$RESOURCE_GROUP" \
    --environment "$ENVIRONMENT"
fi

# Step 5: Verify deployment
log_step "Deployment Verification"
APP_NAME="authframework-${ENVIRONMENT}-api"
log_info "Deploying new image to App Service..."
az webapp config container set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --docker-custom-image-name "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
  --output none

log_info "Restarting App Service..."
az webapp restart --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --output none

log_info "Waiting for App Service to be healthy..."
APP_URL="https://${APP_NAME}.azurewebsites.net"
for i in {1..12}; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${APP_URL}/health" --max-time 15 || echo "000")
  if [[ "$HTTP_STATUS" == "200" ]]; then
    log_success "App Service is healthy (HTTP 200)"
    break
  fi
  log_warn "Attempt $i/12: HTTP ${HTTP_STATUS}, waiting 15s..."
  sleep 15
done

[[ "$HTTP_STATUS" == "200" ]] || { log_error "App Service health check failed after all retries"; exit 1; }

log_step "Deployment Complete"
log_success "Auth Framework deployed successfully!"
log_info "Application URL: ${APP_URL}"
