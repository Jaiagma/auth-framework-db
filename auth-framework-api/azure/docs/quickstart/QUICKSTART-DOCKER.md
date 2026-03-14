# Docker-Based Deployment (5 Minutes)

## Local Development

```bash
cd auth-framework-api

# Copy and fill env vars
cp .env.example .env
# Edit .env with your values

# Start the full stack (PostgreSQL + API)
docker compose -f docker-compose.azure.yml up -d

# Verify
curl http://localhost:8080/health
```

## Build and Push to ACR

```bash
ACR="yourname.azurecr.io"
TAG="$(date +%Y%m%d)-$(git rev-parse --short HEAD)"

# Login to ACR
az acr login --name yourname

# Build (context is auth-framework-api/)
docker build \
  --platform linux/amd64 \
  -t ${ACR}/authframework-api:${TAG} \
  -t ${ACR}/authframework-api:latest \
  -f auth-framework-api/Dockerfile \
  auth-framework-api/

# Push
docker push ${ACR}/authframework-api:${TAG}
docker push ${ACR}/authframework-api:latest
```

## Deploy to App Service

```bash
APP="authframework-prod-api"
RG="rg-authframework-prod"

# Update container image
az webapp config container set \
  --name $APP \
  --resource-group $RG \
  --docker-custom-image-name "${ACR}/authframework-api:${TAG}"

# Restart
az webapp restart --name $APP --resource-group $RG

# Check health
curl https://${APP}.azurewebsites.net/health
```

## Useful Docker Commands

```bash
# View running containers
docker ps

# View API logs
docker logs authframework-api -f

# Shell into API container
docker exec -it authframework-api bash

# Stop stack
docker compose -f auth-framework-api/docker-compose.azure.yml down

# Remove volumes (reset DB)
docker compose -f auth-framework-api/docker-compose.azure.yml down -v
```
