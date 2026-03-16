# Stage 1: Build
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY AuthFramework.sln .
COPY src/AuthFramework.Api/AuthFramework.Api.csproj src/AuthFramework.Api/
COPY src/AuthFramework.Application/AuthFramework.Application.csproj src/AuthFramework.Application/
COPY src/AuthFramework.Core/AuthFramework.Core.csproj src/AuthFramework.Core/
COPY src/AuthFramework.Infrastructure/AuthFramework.Infrastructure.csproj src/AuthFramework.Infrastructure/
COPY src/AuthFramework.Shared/AuthFramework.Shared.csproj src/AuthFramework.Shared/

RUN dotnet restore "AuthFramework.sln"

COPY . .

RUN dotnet publish "src/AuthFramework.Api/AuthFramework.Api.csproj" \
    -c Release \
    -o /app/publish \
    --no-restore

# Stage 2: Runtime
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1001 appgroup \
    && useradd -u 1001 -g appgroup -s /bin/false appuser

COPY --from=build /app/publish .

RUN chown -R appuser:appgroup /app

USER appuser

ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production \
    DOTNET_RUNNING_IN_CONTAINER=true \
    DOTNET_USE_POLLING_FILE_WATCHER=false

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "AuthFramework.Api.dll"]
