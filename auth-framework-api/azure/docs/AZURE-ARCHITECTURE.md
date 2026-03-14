# Azure Architecture Guide

This document describes the architecture of the Auth Framework API deployment on Microsoft
Azure, including component relationships, security boundaries, and data flows.

---

## Table of Contents

1. [High-Level Architecture](#high-level-architecture)
2. [Component Breakdown](#component-breakdown)
3. [Network Architecture](#network-architecture)
4. [Security Architecture](#security-architecture)
5. [Data Flow Diagrams](#data-flow-diagrams)
6. [Resilience and Availability](#resilience-and-availability)

---

## High-Level Architecture

```
                          ┌──────────────────────────────────────────────────────┐
                          │                   AZURE CLOUD                         │
   Internet               │                                                        │
   Clients                │  ┌─────────────────────────────────────────────────┐  │
     │                    │  │           Azure Front Door / CDN                 │  │
     │  HTTPS             │  │    (WAF · Global Load Balancer · TLS Offload)   │  │
     └───────────────────►│  └──────────────────────┬──────────────────────────┘  │
                          │                         │                              │
                          │          ┌──────────────▼──────────────┐              │
                          │          │     App Service Plan (P1v3)  │              │
                          │          │  ┌───────────┐ ┌──────────┐ │              │
                          │          │  │ Production│ │ Staging  │ │              │
                          │          │  │   Slot    │ │  Slot    │ │              │
                          │          │  │  :443     │ │  :443    │ │              │
                          │          │  └─────┬─────┘ └──────────┘ │              │
                          │          └────────│─────────────────────┘              │
                          │                  │  VNet Integration                   │
                          │   ┌──────────────▼──────────────────────────────────┐ │
                          │   │         Virtual Network (10.0.0.0/16)           │ │
                          │   │                                                  │ │
                          │   │  ┌──────────────────┐  ┌────────────────────┐  │ │
                          │   │  │  App Subnet       │  │  Data Subnet       │  │ │
                          │   │  │  10.0.1.0/24      │  │  10.0.2.0/24       │  │ │
                          │   │  │  (delegated to    │  │  (PostgreSQL       │  │ │
                          │   │  │   App Service)    │  │   Flexible Server) │  │ │
                          │   │  └──────────────────┘  └────────────────────┘  │ │
                          │   │                                                  │ │
                          │   │  ┌──────────────────┐                           │ │
                          │   │  │  PE Subnet        │                           │ │
                          │   │  │  10.0.3.0/24      │                           │ │
                          │   │  │  (Private Endpts) │                           │ │
                          │   │  └──────────────────┘                           │ │
                          │   └──────────────────────────────────────────────────┘ │
                          │                                                        │
                          │   Supporting Services                                  │
                          │   ┌──────────────┐  ┌─────────────┐  ┌─────────────┐ │
                          │   │  Key Vault   │  │     ACR     │  │  App        │ │
                          │   │  (Secrets,   │  │  (Container │  │  Insights   │ │
                          │   │   Certs,     │  │   Images)   │  │  + Log      │ │
                          │   │   Keys)      │  │             │  │  Analytics  │ │
                          │   └──────────────┘  └─────────────┘  └─────────────┘ │
                          └──────────────────────────────────────────────────────┘
```

---

## Component Breakdown

### App Service

The application tier runs as a Linux Docker container on Azure App Service.

| Attribute | Value |
|---|---|
| Runtime | Docker container (Linux) |
| SKU | P1v3 (prod) / B2 (dev) |
| Slots | Production + Staging |
| Scale | Auto-scale 2–10 instances |
| VNet | Integrated via subnet delegation |
| Identity | System-assigned Managed Identity |
| Health check | `/health` endpoint, 30-second interval |

The App Service uses **VNet Integration** to route all outbound traffic through the virtual
network. This ensures database and Key Vault traffic stays on the Azure backbone and never
traverses the public internet.

Deployment slots enable **zero-downtime deployments**: new versions are deployed to the
staging slot, validated, then swapped into production. The swap operation is atomic from
the perspective of incoming requests.

### PostgreSQL Flexible Server

The database tier uses Azure Database for PostgreSQL – Flexible Server.

| Attribute | Value |
|---|---|
| Version | PostgreSQL 16 |
| SKU | GP_Standard_D2s_v3 (prod) |
| Storage | 32 GB with auto-grow enabled |
| High Availability | Zone-redundant standby |
| Backup | Automated daily backups, 35-day retention |
| Backup redundancy | Geo-redundant |
| Network | VNet-injected (no public endpoint) |
| Encryption | AES-256 at rest (customer-managed key via Key Vault) |
| SSL | Required (`ssl_mode=require`) |

The Flexible Server is **VNet-injected** into the data subnet. There is no public endpoint.
Only resources within the virtual network (or connected via VNet peering) can reach the
database server.

Row-level security (RLS) policies are defined in `rls_policies.sql` and enforce tenant
isolation at the database level.

### Virtual Network

The VNet provides network isolation and controls all traffic flows between components.

```
VNet: 10.0.0.0/16
├── app-subnet       10.0.1.0/24   App Service VNet Integration
├── data-subnet      10.0.2.0/24   PostgreSQL Flexible Server (VNet injection)
├── pe-subnet        10.0.3.0/24   Private Endpoints (Key Vault, ACR, Storage)
└── bastion-subnet   10.0.4.0/24   Azure Bastion (optional, admin access)
```

Network Security Groups (NSGs) are attached to each subnet with least-privilege rules.
The data subnet NSG, for example, denies all inbound traffic except from the app subnet
on port 5432.

### Key Vault

Azure Key Vault stores all sensitive configuration values.

| Secret | Description |
|---|---|
| `postgres-admin-password` | PostgreSQL administrator password |
| `postgres-connection-string` | Full ADO.NET connection string |
| `app-jwt-signing-key` | JWT signing key (RSA or HMAC) |
| `app-encryption-key` | Data encryption key |
| `sendgrid-api-key` | Email service API key |

The App Service accesses Key Vault secrets through its **Managed Identity** and Key Vault
references in the application settings (e.g., `@Microsoft.KeyVault(SecretUri=...)`). No
secrets are stored in environment variables or configuration files.

Key Vault is accessed through a **private endpoint** in the PE subnet, preventing any
access from the public internet.

### Azure Container Registry (ACR)

ACR stores Docker images for the application.

| Attribute | Value |
|---|---|
| SKU | Premium (geo-replication, private endpoint) |
| Geo-replication | Secondary region enabled for production |
| Private endpoint | PE subnet |
| Admin account | Disabled |
| Authentication | Managed Identity (AcrPull role) |

The App Service uses its Managed Identity with the `AcrPull` role to pull images from ACR.
No username/password credentials are required.

### Application Insights & Log Analytics

All telemetry flows to a **Log Analytics Workspace** with Application Insights providing
the application-level SDK.

| Component | Purpose |
|---|---|
| Log Analytics Workspace | Central log store, retention 90 days (prod) |
| Application Insights | APM: request traces, exceptions, dependencies |
| Diagnostic Settings | Platform logs from App Service, PostgreSQL, Key Vault |

---

## Network Architecture

### Traffic Flow (Inbound)

```
Client Request
     │
     ▼ HTTPS (TLS 1.2+)
Azure Front Door
     │ WAF rules applied
     │ DDoS protection
     ▼
App Service (Production Slot)
     │ App processes request
     │ Outbound via VNet Integration
     ├──► PostgreSQL (port 5432, data-subnet)
     ├──► Key Vault (port 443, private endpoint)
     └──► ACR (port 443, private endpoint)
```

### NSG Rules Summary

**app-subnet NSG (inbound)**

| Priority | Name | Port | Source | Action |
|---|---|---|---|---|
| 100 | AllowAzureFrontDoor | 443 | AzureFrontDoor.Backend | Allow |
| 200 | AllowHealthProbe | 443 | AzureLoadBalancer | Allow |
| 4096 | DenyAll | * | * | Deny |

**data-subnet NSG (inbound)**

| Priority | Name | Port | Source | Action |
|---|---|---|---|---|
| 100 | AllowAppSubnet | 5432 | 10.0.1.0/24 | Allow |
| 4096 | DenyAll | * | * | Deny |

---

## Security Architecture

### Identity and Access

```
App Service (Managed Identity)
     │
     ├──► Key Vault (Key Vault Secrets User)
     ├──► ACR (AcrPull)
     └──► Storage Account (Storage Blob Data Reader)

Developers
     │
     ├──► Azure AD authentication required for all portal access
     ├──► JIT (Just-In-Time) access for database admin
     └──► Bastion Host for VM/container access (no public SSH)
```

### Defense in Depth

```
Layer 1: Azure DDoS Protection Standard
Layer 2: Azure Front Door WAF (OWASP rule set)
Layer 3: NSG rules on each subnet
Layer 4: Private endpoints (no public access to Key Vault, ACR, DB)
Layer 5: Managed Identity (no stored credentials)
Layer 6: TLS 1.2+ enforced end-to-end
Layer 7: PostgreSQL SSL required + certificate validation
Layer 8: Row-level security in PostgreSQL
Layer 9: Application-level authorization (JWT + RBAC)
```

---

## Data Flow Diagrams

### Authentication Request Flow

```
Client                App Service              PostgreSQL            Key Vault
  │                       │                        │                     │
  │  POST /auth/login      │                        │                     │
  ├──────────────────────►│                        │                     │
  │                       │  Fetch JWT signing key  │                     │
  │                       ├────────────────────────────────────────────►│
  │                       │◄────────────────────────────────────────────┤
  │                       │  SELECT user WHERE email=?                   │
  │                       ├──────────────────────►│                     │
  │                       │◄──────────────────────┤                     │
  │                       │  Verify password hash  │                     │
  │                       │  Sign JWT              │                     │
  │  200 OK + JWT token    │                        │                     │
  │◄──────────────────────┤                        │                     │
```

### Container Startup Flow

```
App Service                   ACR                Key Vault
     │                          │                     │
     │  Pull image (Managed ID) │                     │
     ├─────────────────────────►│                     │
     │◄─────────────────────────┤                     │
     │  App process starts       │                     │
     │  Resolve KV references    │                     │
     ├──────────────────────────────────────────────►│
     │◄──────────────────────────────────────────────┤
     │  Apply configuration      │                     │
     │  Run health check         │                     │
     │  Accept traffic           │                     │
```
