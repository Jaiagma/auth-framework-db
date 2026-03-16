# 5-Minute Terraform Setup

## Prerequisites
- Azure CLI (`az login` completed)
- Terraform >= 1.5
- Contributor access to an Azure subscription

## Steps

```bash
# 1. Clone and navigate
cd auth-framework-api/azure/terraform

# 2. Copy and edit vars
cp terraform.tfvars.example terraform.tfvars
# Set environment, alert_email, etc.

# 3. Export secrets as env vars (never store in .tfvars)
export TF_VAR_db_password="$(openssl rand -base64 24)"
export TF_VAR_jwt_secret_key="$(openssl rand -base64 48)"
export TF_VAR_encryption_key="$(openssl rand -hex 16)"

# 4. Init (with local state for quick start)
terraform init

# 5. Plan
terraform plan -var="environment=dev"

# 6. Apply
terraform apply -var="environment=dev"
```

## Outputs
After apply, retrieve key values:
```bash
terraform output app_service_url
terraform output postgresql_fqdn
terraform output key_vault_uri
```
