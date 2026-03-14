# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy solution and project files for dependency restoration
COPY AuthFramework.sln ./
COPY src/AuthFramework.Core/AuthFramework.Core.csproj src/AuthFramework.Core/
COPY src/AuthFramework.Application/AuthFramework.Application.csproj src/AuthFramework.Application/
COPY src/AuthFramework.Infrastructure/AuthFramework.Infrastructure.csproj src/AuthFramework.Infrastructure/
COPY src/AuthFramework.Shared/AuthFramework.Shared.csproj src/AuthFramework.Shared/
COPY src/AuthFramework.Api/AuthFramework.Api.csproj src/AuthFramework.Api/

RUN dotnet restore src/AuthFramework.Api/AuthFramework.Api.csproj

# Copy all source and publish
COPY src/ src/
RUN dotnet publish src/AuthFramework.Api/AuthFramework.Api.csproj \
    -c Release -o /app/publish \
    --no-restore \
    /p:UseAppHost=false

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app

# Create non-root user
RUN addgroup --system --gid 1001 appgroup \
 && adduser  --system --uid 1001 --ingroup appgroup appuser

COPY --from=build /app/publish ./
RUN mkdir -p /app/logs && chown -R appuser:appgroup /app

USER appuser

EXPOSE 8080
ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:8080/health || exit 1

ENTRYPOINT ["dotnet", "AuthFramework.Api.dll"]
