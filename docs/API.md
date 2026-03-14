# API Reference

Base URL: `/api`  
All endpoints require the `X-Tenant-ID` header unless noted otherwise.  
Authenticated endpoints require `Authorization: Bearer <access_token>`.

---

## Table of Contents

1. [Common Headers & Conventions](#common-headers--conventions)
2. [Error Codes](#error-codes)
3. [Rate Limiting](#rate-limiting)
4. [Authentication Endpoints](#authentication-endpoints)
5. [MFA Endpoints](#mfa-endpoints)
6. [OAuth Endpoints](#oauth-endpoints)
7. [SSO Endpoints](#sso-endpoints)
8. [User Endpoints](#user-endpoints)
9. [Admin Endpoints](#admin-endpoints)

---

## Common Headers & Conventions

| Header            | Required | Description                                                      |
|-------------------|----------|------------------------------------------------------------------|
| `X-Tenant-ID`     | Yes      | UUID of the tenant context for the request                       |
| `Authorization`   | Varies   | `Bearer <access_token>` for authenticated endpoints              |
| `Content-Type`    | Yes      | `application/json` for all request bodies                        |
| `Accept`          | No       | `application/json` (default)                                     |
| `X-Request-ID`    | No       | Client-supplied idempotency / correlation UUID                   |

All timestamps are **ISO 8601 UTC** (e.g., `2025-01-15T12:00:00Z`).  
All IDs are **UUID v7** strings unless otherwise noted.  
Successful responses use `2xx` status codes with a JSON body.  
Error responses always include `{ "error": "<code>", "message": "<human-readable>" }`.

---

## Error Codes

| HTTP Status | Error Code                    | Description                                  |
|-------------|-------------------------------|----------------------------------------------|
| 400         | `validation_error`            | Request body failed validation               |
| 400         | `invalid_token`               | Malformed or expired token                   |
| 400         | `mfa_code_invalid`            | TOTP/backup code is wrong or expired         |
| 401         | `unauthorized`                | Missing or invalid Bearer token              |
| 401         | `credentials_invalid`         | Wrong email or password                      |
| 401         | `token_expired`               | Access token has expired                     |
| 401         | `refresh_token_expired`       | Refresh token has expired                    |
| 403         | `forbidden`                   | Authenticated but not authorized             |
| 403         | `tenant_mismatch`             | Token tenant does not match X-Tenant-ID      |
| 403         | `account_locked`              | Account locked after repeated failures       |
| 403         | `email_not_verified`          | Email must be verified before login          |
| 404         | `not_found`                   | Resource does not exist                      |
| 409         | `conflict`                    | Resource already exists (e.g., duplicate email) |
| 422         | `mfa_required`                | MFA step required to complete authentication |
| 429         | `rate_limit_exceeded`         | Too many requests                            |
| 500         | `internal_error`              | Unexpected server error                      |

---

## Rate Limiting

Rate limits are applied per **tenant + IP** combination and returned in response headers:

| Header                  | Description                              |
|-------------------------|------------------------------------------|
| `X-RateLimit-Limit`     | Maximum requests allowed in the window  |
| `X-RateLimit-Remaining` | Requests remaining in current window    |
| `X-RateLimit-Reset`     | Unix timestamp when the window resets   |
| `Retry-After`           | Seconds to wait (only on 429 responses) |

Default limits by category:

| Category            | Limit         |
|---------------------|---------------|
| Login / Register    | 10 / minute   |
| Password reset      | 5 / hour      |
| Email verification  | 5 / hour      |
| MFA verification    | 10 / minute   |
| Token refresh       | 60 / minute   |
| General API         | 300 / minute  |
| Admin endpoints     | 120 / minute  |

---

## Authentication Endpoints

### POST /api/auth/register

Register a new user account within a tenant.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "email": "user@example.com",
  "password": "S3cure!Pass#2025",
  "firstName": "Jane",
  "lastName": "Doe",
  "locale": "en-US",
  "timezone": "America/New_York",
  "consentToTerms": true,
  "consentToMarketing": false
}
```

| Field                | Type    | Required | Description                           |
|----------------------|---------|----------|---------------------------------------|
| `email`              | string  | Yes      | Valid email address                   |
| `password`           | string  | Yes      | Min 12 chars, complexity enforced     |
| `firstName`          | string  | Yes      | 1–100 characters                      |
| `lastName`           | string  | Yes      | 1–100 characters                      |
| `locale`             | string  | No       | BCP-47 locale tag (default: `en-US`)  |
| `timezone`           | string  | No       | IANA timezone (default: `UTC`)        |
| `consentToTerms`     | boolean | Yes      | Must be `true` to proceed             |
| `consentToMarketing` | boolean | No       | Default `false`                       |

**Response 201 Created**

```json
{
  "userId": "018e7f4a-1234-7abc-8def-000000000001",
  "email": "user@example.com",
  "message": "Registration successful. Please verify your email.",
  "emailVerificationRequired": true
}
```

**Errors:** `validation_error` (400), `conflict` (409 – email already exists), `rate_limit_exceeded` (429)

---

### POST /api/auth/login

Authenticate with email and password.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "email": "user@example.com",
  "password": "S3cure!Pass#2025",
  "deviceName": "Chrome on macOS",
  "rememberDevice": false
}
```

| Field            | Type    | Required | Description                                   |
|------------------|---------|----------|-----------------------------------------------|
| `email`          | string  | Yes      | Registered email address                      |
| `password`       | string  | Yes      | Account password                              |
| `deviceName`     | string  | No       | Human-readable device identifier              |
| `rememberDevice` | boolean | No       | Extend session lifetime (default: `false`)    |

**Response 200 OK – No MFA**

```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "v2.refresh.abc123...",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "sessionId": "018e7f4a-2222-7abc-8def-000000000002"
}
```

**Response 200 OK – MFA Required**

```json
{
  "mfaRequired": true,
  "mfaToken": "mfa.intermediate.xyz...",
  "mfaMethods": ["totp", "backup_code"],
  "expiresIn": 300
}
```

**Errors:** `credentials_invalid` (401), `email_not_verified` (403), `account_locked` (403), `mfa_required` (422), `rate_limit_exceeded` (429)

---

### POST /api/auth/logout

Revoke the current session and invalidate tokens.

**Headers**

| Header          | Required | Value              |
|-----------------|----------|--------------------|
| X-Tenant-ID     | Yes      | `<tenant-uuid>`    |
| Authorization   | Yes      | `Bearer <token>`   |
| Content-Type    | Yes      | `application/json` |

**Request Body**

```json
{
  "refreshToken": "v2.refresh.abc123...",
  "allSessions": false
}
```

| Field          | Type    | Required | Description                                           |
|----------------|---------|----------|-------------------------------------------------------|
| `refreshToken` | string  | No       | If provided, also revokes this refresh token          |
| `allSessions`  | boolean | No       | If `true`, revokes all sessions for the user          |

**Response 204 No Content**

**Errors:** `unauthorized` (401)

---

### POST /api/auth/refresh-token

Exchange a refresh token for a new access token.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "refreshToken": "v2.refresh.abc123..."
}
```

**Response 200 OK**

```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "v2.refresh.def456...",
  "tokenType": "Bearer",
  "expiresIn": 900
}
```

**Errors:** `invalid_token` (400), `refresh_token_expired` (401), `rate_limit_exceeded` (429)

> Refresh tokens are rotated on each use. The old token is immediately invalidated.

---

### POST /api/auth/password-reset

Initiate a password reset flow by sending a reset email.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "email": "user@example.com"
}
```

**Response 200 OK** *(always 200 to prevent user enumeration)*

```json
{
  "message": "If an account with that email exists, a reset link has been sent."
}
```

**Errors:** `rate_limit_exceeded` (429)

---

### POST /api/auth/password-reset/confirm

Complete the password reset using the token from the email.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "token": "reset.token.abc123...",
  "newPassword": "N3wS3cure!Pass#2025"
}
```

**Response 200 OK**

```json
{
  "message": "Password updated successfully. All sessions have been revoked."
}
```

**Errors:** `invalid_token` (400), `validation_error` (400), `rate_limit_exceeded` (429)

---

### POST /api/auth/verify-email

Verify a user's email address using the token sent during registration.

**Headers**

| Header        | Required | Value              |
|---------------|----------|--------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`    |
| Content-Type  | Yes      | `application/json` |

**Request Body**

```json
{
  "token": "verify.email.abc123..."
}
```

**Response 200 OK**

```json
{
  "message": "Email verified successfully.",
  "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "v2.refresh.abc123...",
  "tokenType": "Bearer",
  "expiresIn": 900
}
```

**Errors:** `invalid_token` (400), `rate_limit_exceeded` (429)

---

### GET /api/auth/session

Get details about the current authenticated session.

**Headers**

| Header          | Required | Value            |
|-----------------|----------|------------------|
| X-Tenant-ID     | Yes      | `<tenant-uuid>`  |
| Authorization   | Yes      | `Bearer <token>` |

**Response 200 OK**

```json
{
  "sessionId": "018e7f4a-2222-7abc-8def-000000000002",
  "userId": "018e7f4a-1234-7abc-8def-000000000001",
  "tenantId": "018e7f4a-0000-7abc-8def-000000000000",
  "createdAt": "2025-01-15T10:00:00Z",
  "lastActivityAt": "2025-01-15T12:00:00Z",
  "expiresAt": "2025-01-15T12:15:00Z",
  "ipAddress": "203.0.113.42",
  "userAgent": "Mozilla/5.0 ...",
  "deviceName": "Chrome on macOS",
  "mfaVerified": true
}
```

**Errors:** `unauthorized` (401)

---

## MFA Endpoints

All MFA endpoints require `Authorization: Bearer <token>` and `X-Tenant-ID`.

### POST /api/mfa/enroll

Begin enrolling a new MFA device (TOTP).

**Request Body**

```json
{
  "method": "totp",
  "deviceName": "Authenticator App"
}
```

| Field        | Type   | Required | Description                              |
|--------------|--------|----------|------------------------------------------|
| `method`     | string | Yes      | `totp` (Time-based OTP)                  |
| `deviceName` | string | Yes      | Friendly name for the device             |

**Response 200 OK**

```json
{
  "enrollmentId": "018e7f4a-3333-7abc-8def-000000000003",
  "method": "totp",
  "secret": "JBSWY3DPEHPK3PXP",
  "qrCodeUri": "otpauth://totp/MyApp:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=MyApp",
  "qrCodeImage": "data:image/png;base64,iVBORw0KGgo...",
  "backupCodes": [
    "ABCD-1234",
    "EFGH-5678",
    "IJKL-9012",
    "MNOP-3456",
    "QRST-7890",
    "UVWX-1234",
    "YZAB-5678",
    "CDEF-9012"
  ],
  "expiresIn": 600
}
```

> The enrollment is not active until confirmed with `POST /api/mfa/verify`.

---

### POST /api/mfa/verify

Confirm MFA enrollment or complete an MFA challenge during login.

**Request Body – Enrollment confirmation**

```json
{
  "enrollmentId": "018e7f4a-3333-7abc-8def-000000000003",
  "code": "123456"
}
```

**Request Body – Login MFA challenge**

```json
{
  "mfaToken": "mfa.intermediate.xyz...",
  "code": "123456",
  "method": "totp"
}
```

| Field          | Type   | Required | Description                                             |
|----------------|--------|----------|---------------------------------------------------------|
| `enrollmentId` | string | Cond.    | Required for enrollment confirmation                    |
| `mfaToken`     | string | Cond.    | Required for login MFA challenge                        |
| `code`         | string | Yes      | 6-digit TOTP code or 8-character backup code            |
| `method`       | string | No       | `totp` or `backup_code` (default: `totp`)               |

**Response 200 OK – Enrollment confirmed**

```json
{
  "message": "MFA device enrolled successfully.",
  "deviceId": "018e7f4a-4444-7abc-8def-000000000004"
}
```

**Response 200 OK – Login MFA challenge**

```json
{
  "accessToken": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refreshToken": "v2.refresh.abc123...",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "sessionId": "018e7f4a-2222-7abc-8def-000000000002"
}
```

**Errors:** `mfa_code_invalid` (400), `invalid_token` (400), `rate_limit_exceeded` (429)

---

### GET /api/mfa/devices

List all enrolled MFA devices for the current user.

**Response 200 OK**

```json
{
  "devices": [
    {
      "deviceId": "018e7f4a-4444-7abc-8def-000000000004",
      "method": "totp",
      "deviceName": "Authenticator App",
      "createdAt": "2025-01-10T09:00:00Z",
      "lastUsedAt": "2025-01-15T11:30:00Z",
      "isDefault": true
    }
  ]
}
```

---

### DELETE /api/mfa/devices/{deviceId}

Remove an enrolled MFA device.

**Path Parameters**

| Parameter  | Type   | Description              |
|------------|--------|--------------------------|
| `deviceId` | UUID   | ID of the device to remove |

**Response 204 No Content**

**Errors:** `not_found` (404), `forbidden` (403 – cannot remove last device if MFA is required)

---

### POST /api/mfa/recovery-codes/regenerate

Regenerate backup/recovery codes, invalidating all existing ones.

**Response 200 OK**

```json
{
  "backupCodes": [
    "ABCD-1234",
    "EFGH-5678",
    "IJKL-9012",
    "MNOP-3456",
    "QRST-7890",
    "UVWX-1234",
    "YZAB-5678",
    "CDEF-9012"
  ],
  "message": "Store these codes securely. They will not be shown again."
}
```

---

## OAuth Endpoints

### POST /api/oauth/applications

Register a new OAuth 2.0 application (requires admin or developer role).

**Headers**

| Header          | Required | Value              |
|-----------------|----------|--------------------|
| X-Tenant-ID     | Yes      | `<tenant-uuid>`    |
| Authorization   | Yes      | `Bearer <token>`   |
| Content-Type    | Yes      | `application/json` |

**Request Body**

```json
{
  "name": "My Application",
  "description": "OAuth client for my app",
  "redirectUris": [
    "https://myapp.example.com/callback",
    "http://localhost:3000/callback"
  ],
  "scopes": ["openid", "profile", "email"],
  "applicationType": "web",
  "grantTypes": ["authorization_code", "refresh_token"]
}
```

| Field             | Type     | Required | Description                                            |
|-------------------|----------|----------|--------------------------------------------------------|
| `name`            | string   | Yes      | Display name for the application                       |
| `description`     | string   | No       | Optional description                                   |
| `redirectUris`    | string[] | Yes      | Allowed redirect URIs (must use HTTPS in production)   |
| `scopes`          | string[] | Yes      | Requested OAuth scopes                                 |
| `applicationType` | string   | Yes      | `web`, `native`, `spa`                                 |
| `grantTypes`      | string[] | Yes      | `authorization_code`, `client_credentials`, `refresh_token` |

**Response 201 Created**

```json
{
  "clientId": "018e7f4a-5555-7abc-8def-000000000005",
  "clientSecret": "cs_live_abc123...",
  "name": "My Application",
  "redirectUris": ["https://myapp.example.com/callback"],
  "scopes": ["openid", "profile", "email"],
  "createdAt": "2025-01-15T12:00:00Z"
}
```

> Store `clientSecret` immediately – it is shown only once.

---

### GET /api/oauth/applications

List all OAuth applications for the current tenant.

**Response 200 OK**

```json
{
  "applications": [
    {
      "clientId": "018e7f4a-5555-7abc-8def-000000000005",
      "name": "My Application",
      "applicationType": "web",
      "redirectUris": ["https://myapp.example.com/callback"],
      "scopes": ["openid", "profile", "email"],
      "createdAt": "2025-01-15T12:00:00Z",
      "isActive": true
    }
  ],
  "total": 1
}
```

---

### GET /api/oauth/authorize

Initiate the OAuth 2.0 Authorization Code flow. This is a browser redirect endpoint.

**Query Parameters**

| Parameter               | Required | Description                                          |
|-------------------------|----------|------------------------------------------------------|
| `response_type`         | Yes      | Must be `code`                                       |
| `client_id`             | Yes      | Registered OAuth application client ID               |
| `redirect_uri`          | Yes      | Must exactly match a registered redirect URI         |
| `scope`                 | Yes      | Space-separated list of requested scopes             |
| `state`                 | Yes      | CSRF protection value (random string)                |
| `code_challenge`        | Yes      | PKCE code challenge (S256)                           |
| `code_challenge_method` | Yes      | Must be `S256`                                       |
| `nonce`                 | No       | Replay prevention for OIDC ID tokens                 |

**Example Request**

```
GET /api/oauth/authorize
  ?response_type=code
  &client_id=018e7f4a-5555-7abc-8def-000000000005
  &redirect_uri=https%3A%2F%2Fmyapp.example.com%2Fcallback
  &scope=openid%20profile%20email
  &state=random-csrf-token
  &code_challenge=abc123...
  &code_challenge_method=S256
```

**Response:** HTTP 302 redirect to login/consent page, then redirects to `redirect_uri?code=<auth_code>&state=<state>`

---

### POST /api/oauth/token

Exchange an authorization code or refresh a token.

**Headers**

| Header        | Required | Value                                     |
|---------------|----------|-------------------------------------------|
| Content-Type  | Yes      | `application/x-www-form-urlencoded`       |

**Request Body – Authorization Code**

```
grant_type=authorization_code
&code=authcode.abc123...
&redirect_uri=https://myapp.example.com/callback
&client_id=018e7f4a-5555-7abc-8def-000000000005
&client_secret=cs_live_abc123...
&code_verifier=pkce-verifier-abc123...
```

**Request Body – Refresh Token**

```
grant_type=refresh_token
&refresh_token=v2.refresh.abc123...
&client_id=018e7f4a-5555-7abc-8def-000000000005
&client_secret=cs_live_abc123...
```

**Response 200 OK**

```json
{
  "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "Bearer",
  "expires_in": 900,
  "refresh_token": "v2.refresh.def456...",
  "scope": "openid profile email",
  "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Errors:** `invalid_client` (401), `invalid_grant` (400), `invalid_request` (400)

---

### POST /api/oauth/revoke

Revoke an access token or refresh token (RFC 7009).

**Headers**

| Header        | Required | Value                               |
|---------------|----------|-------------------------------------|
| Content-Type  | Yes      | `application/x-www-form-urlencoded` |

**Request Body**

```
token=v2.refresh.abc123...
&token_type_hint=refresh_token
&client_id=018e7f4a-5555-7abc-8def-000000000005
&client_secret=cs_live_abc123...
```

**Response 200 OK** *(always 200, per RFC 7009)*

```json
{}
```

---

### POST /api/oauth/introspect

Validate and inspect a token (RFC 7662). Requires client authentication.

**Request Body (form-encoded)**

```
token=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
&client_id=018e7f4a-5555-7abc-8def-000000000005
&client_secret=cs_live_abc123...
```

**Response 200 OK – Active token**

```json
{
  "active": true,
  "sub": "018e7f4a-1234-7abc-8def-000000000001",
  "client_id": "018e7f4a-5555-7abc-8def-000000000005",
  "scope": "openid profile email",
  "exp": 1737028800,
  "iat": 1737027900,
  "iss": "https://auth.example.com",
  "aud": "018e7f4a-5555-7abc-8def-000000000005"
}
```

**Response 200 OK – Inactive/expired token**

```json
{
  "active": false
}
```

---

## SSO Endpoints

### GET /api/sso/providers

List available SSO providers configured for the tenant.

**Headers**

| Header       | Required | Value           |
|--------------|----------|-----------------|
| X-Tenant-ID  | Yes      | `<tenant-uuid>` |

**Response 200 OK**

```json
{
  "providers": [
    {
      "id": "018e7f4a-6666-7abc-8def-000000000006",
      "name": "Corporate SAML IdP",
      "protocol": "saml",
      "slug": "corporate-saml",
      "iconUrl": "https://cdn.example.com/icons/saml.svg",
      "isEnabled": true
    },
    {
      "id": "018e7f4a-7777-7abc-8def-000000000007",
      "name": "Google Workspace",
      "protocol": "oidc",
      "slug": "google",
      "iconUrl": "https://cdn.example.com/icons/google.svg",
      "isEnabled": true
    }
  ]
}
```

---

### GET /api/sso/login/{provider}

Initiate SSO login with the specified provider. Browser redirect endpoint.

**Path Parameters**

| Parameter  | Type   | Description                                                |
|------------|--------|------------------------------------------------------------|
| `provider` | string | Provider slug (e.g., `google`, `corporate-saml`)           |

**Query Parameters**

| Parameter     | Required | Description                              |
|---------------|----------|------------------------------------------|
| `redirect_uri`| No       | Post-login redirect (must be allow-listed)|
| `state`       | Yes      | CSRF state token                         |

**Response:** HTTP 302 redirect to IdP login page.

---

### GET /api/sso/callback

Handle SSO callback from identity provider (SAML assertion POST or OIDC code callback).

**Query Parameters (OIDC)**

| Parameter | Required | Description                   |
|-----------|----------|-------------------------------|
| `code`    | Yes      | Authorization code from IdP   |
| `state`   | Yes      | CSRF state token               |

**POST body (SAML):** `SAMLResponse` form field containing Base64-encoded assertion.

**Response:** HTTP 302 redirect to application with session established, or to error page.

---

### POST /api/sso/logout

Initiate SSO logout (SP-initiated).

**Headers**

| Header        | Required | Value            |
|---------------|----------|------------------|
| X-Tenant-ID   | Yes      | `<tenant-uuid>`  |
| Authorization | Yes      | `Bearer <token>` |

**Response 200 OK**

```json
{
  "message": "Session terminated.",
  "sloUrl": "https://idp.example.com/slo?SAMLRequest=..."
}
```

| Field    | Description                                                  |
|----------|--------------------------------------------------------------|
| `sloUrl` | If the IdP supports SLO, redirect the browser here          |

---

## User Endpoints

All user endpoints require `Authorization: Bearer <token>` and `X-Tenant-ID`.

### GET /api/users/me

Get the current authenticated user's profile.

**Response 200 OK**

```json
{
  "userId": "018e7f4a-1234-7abc-8def-000000000001",
  "email": "user@example.com",
  "emailVerified": true,
  "firstName": "Jane",
  "lastName": "Doe",
  "displayName": "Jane Doe",
  "avatarUrl": null,
  "locale": "en-US",
  "timezone": "America/New_York",
  "mfaEnabled": true,
  "createdAt": "2025-01-01T00:00:00Z",
  "lastLoginAt": "2025-01-15T10:00:00Z",
  "roles": ["user"],
  "tenantId": "018e7f4a-0000-7abc-8def-000000000000"
}
```

---

### PATCH /api/users/me

Update the current user's profile.

**Request Body**

```json
{
  "firstName": "Jane",
  "lastName": "Smith",
  "displayName": "Jane Smith",
  "locale": "en-GB",
  "timezone": "Europe/London",
  "avatarUrl": "https://cdn.example.com/avatars/user123.jpg"
}
```

All fields are optional. Only provided fields are updated.

**Response 200 OK** – Returns updated user profile (same schema as GET /api/users/me).

**Errors:** `validation_error` (400)

---

### GET /api/users/me/sessions

List all active sessions for the current user.

**Response 200 OK**

```json
{
  "sessions": [
    {
      "sessionId": "018e7f4a-2222-7abc-8def-000000000002",
      "createdAt": "2025-01-15T10:00:00Z",
      "lastActivityAt": "2025-01-15T12:00:00Z",
      "expiresAt": "2025-01-15T12:15:00Z",
      "ipAddress": "203.0.113.42",
      "userAgent": "Mozilla/5.0 ...",
      "deviceName": "Chrome on macOS",
      "isCurrent": true,
      "mfaVerified": true,
      "location": "New York, US"
    }
  ]
}
```

---

### DELETE /api/users/me/sessions/{sessionId}

Revoke a specific session.

**Path Parameters**

| Parameter   | Type | Description                |
|-------------|------|----------------------------|
| `sessionId` | UUID | Session ID to revoke       |

**Response 204 No Content**

**Errors:** `not_found` (404)

---

### GET /api/users/me/preferences

Get user notification and privacy preferences.

**Response 200 OK**

```json
{
  "notifications": {
    "emailLoginAlert": true,
    "emailPasswordChanged": true,
    "emailNewDevice": true,
    "emailMarketing": false
  },
  "privacy": {
    "profileVisible": false,
    "activityTracking": false
  }
}
```

---

### PUT /api/users/me/preferences

Replace user preferences.

**Request Body** – Same schema as GET response.

**Response 200 OK** – Returns updated preferences.

---

### GET /api/users/me/data-export

Request a full export of the user's personal data (GDPR Article 20 – Data Portability).

**Response 200 OK**

```json
{
  "exportId": "018e7f4a-8888-7abc-8def-000000000008",
  "status": "pending",
  "message": "Your data export is being prepared. You will receive an email when it is ready.",
  "estimatedCompletionTime": "2025-01-15T13:00:00Z"
}
```

> Exports are delivered via secure download link sent to the verified email address.

---

### POST /api/users/me/delete

Request account deletion (GDPR Article 17 – Right to Erasure).

**Request Body**

```json
{
  "reason": "No longer using the service",
  "confirmEmail": "user@example.com",
  "password": "S3cure!Pass#2025"
}
```

| Field          | Type   | Required | Description                                       |
|----------------|--------|----------|---------------------------------------------------|
| `reason`       | string | No       | Optional reason for deletion                      |
| `confirmEmail` | string | Yes      | Must match the account email (confirmation check) |
| `password`     | string | Yes      | Current password to confirm identity              |

**Response 200 OK**

```json
{
  "message": "Account deletion scheduled. Your account will be permanently deleted within 30 days.",
  "deletionScheduledAt": "2025-02-14T12:00:00Z",
  "cancellationDeadline": "2025-01-22T12:00:00Z"
}
```

> Users can cancel the deletion request by logging in again within the cancellation window.

**Errors:** `credentials_invalid` (401), `validation_error` (400)

---

## Admin Endpoints

All admin endpoints require `Authorization: Bearer <token>` with an `admin` or `super_admin` role and `X-Tenant-ID`.

### GET /api/admin/users

List users in the tenant with pagination and filtering.

**Query Parameters**

| Parameter  | Type    | Description                                         |
|------------|---------|-----------------------------------------------------|
| `page`     | integer | Page number (default: 1)                            |
| `pageSize` | integer | Results per page (default: 20, max: 100)            |
| `search`   | string  | Search by email, first name, or last name           |
| `role`     | string  | Filter by role (`user`, `admin`, `super_admin`)     |
| `status`   | string  | Filter by status (`active`, `locked`, `deleted`)   |
| `sort`     | string  | Sort field: `createdAt`, `email`, `lastLoginAt`     |
| `order`    | string  | `asc` or `desc` (default: `desc`)                   |

**Response 200 OK**

```json
{
  "users": [
    {
      "userId": "018e7f4a-1234-7abc-8def-000000000001",
      "email": "user@example.com",
      "firstName": "Jane",
      "lastName": "Doe",
      "roles": ["user"],
      "status": "active",
      "emailVerified": true,
      "mfaEnabled": true,
      "createdAt": "2025-01-01T00:00:00Z",
      "lastLoginAt": "2025-01-15T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 1,
    "totalPages": 1
  }
}
```

---

### GET /api/admin/users/{userId}

Get detailed information about a specific user.

**Response 200 OK** – Full user object including roles, sessions count, MFA devices, and audit summary.

---

### PATCH /api/admin/users/{userId}

Update a user's status, roles, or attributes.

**Request Body**

```json
{
  "roles": ["user", "admin"],
  "status": "active",
  "forcePasswordReset": false,
  "lockReason": null
}
```

**Response 200 OK** – Updated user object.

---

### DELETE /api/admin/users/{userId}

Permanently delete a user account (admin-initiated).

**Response 204 No Content**

**Errors:** `not_found` (404), `forbidden` (403 – cannot delete own account)

---

### POST /api/admin/users/{userId}/lock

Lock a user account to prevent login.

**Request Body**

```json
{
  "reason": "Suspicious activity detected",
  "durationMinutes": 1440
}
```

**Response 200 OK**

```json
{
  "message": "User account locked.",
  "lockedUntil": "2025-01-16T12:00:00Z"
}
```

---

### POST /api/admin/users/{userId}/unlock

Unlock a previously locked user account.

**Response 200 OK**

```json
{
  "message": "User account unlocked."
}
```

---

### GET /api/admin/audit-logs

Query the audit log for security and compliance events.

**Query Parameters**

| Parameter    | Type     | Description                                          |
|--------------|----------|------------------------------------------------------|
| `userId`     | UUID     | Filter by user                                       |
| `eventType`  | string   | Filter by event type (e.g., `login`, `logout`)       |
| `from`       | datetime | Start of time range (ISO 8601)                       |
| `to`         | datetime | End of time range (ISO 8601)                         |
| `page`       | integer  | Page number (default: 1)                             |
| `pageSize`   | integer  | Results per page (default: 50, max: 200)             |

**Response 200 OK**

```json
{
  "logs": [
    {
      "logId": "018e7f4a-9999-7abc-8def-000000000009",
      "userId": "018e7f4a-1234-7abc-8def-000000000001",
      "eventType": "login_success",
      "ipAddress": "203.0.113.42",
      "userAgent": "Mozilla/5.0 ...",
      "metadata": { "mfaUsed": true },
      "createdAt": "2025-01-15T10:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "total": 1,
    "totalPages": 1
  }
}
```

---

### GET /api/admin/security-events

List security events requiring attention (failed logins, locked accounts, suspicious activity).

**Query Parameters**

| Parameter   | Type     | Description                                    |
|-------------|----------|------------------------------------------------|
| `severity`  | string   | `low`, `medium`, `high`, `critical`            |
| `resolved`  | boolean  | Filter resolved/unresolved events              |
| `from`      | datetime | Start of time range                            |
| `to`        | datetime | End of time range                              |
| `page`      | integer  | Page number (default: 1)                       |
| `pageSize`  | integer  | Results per page (default: 20, max: 100)       |

**Response 200 OK**

```json
{
  "events": [
    {
      "eventId": "018e7f4a-aaaa-7abc-8def-00000000000a",
      "type": "brute_force_detected",
      "severity": "high",
      "userId": "018e7f4a-1234-7abc-8def-000000000001",
      "ipAddress": "198.51.100.99",
      "description": "10 failed login attempts in 5 minutes",
      "resolved": false,
      "createdAt": "2025-01-15T09:55:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 1,
    "totalPages": 1
  }
}
```

---

### GET /api/admin/tenants

List all tenants (super admin only).

**Response 200 OK**

```json
{
  "tenants": [
    {
      "tenantId": "018e7f4a-0000-7abc-8def-000000000000",
      "name": "Acme Corp",
      "slug": "acme",
      "plan": "enterprise",
      "status": "active",
      "dataResidency": "us-east-1",
      "userCount": 250,
      "createdAt": "2024-06-01T00:00:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "total": 1,
    "totalPages": 1
  }
}
```

---

### POST /api/admin/tenants

Create a new tenant (super admin only).

**Request Body**

```json
{
  "name": "New Corp",
  "slug": "new-corp",
  "plan": "starter",
  "dataResidency": "eu-west-1",
  "adminEmail": "admin@newcorp.example.com",
  "settings": {
    "mfaRequired": false,
    "passwordMinLength": 12,
    "sessionDurationMinutes": 60
  }
}
```

**Response 201 Created**

```json
{
  "tenantId": "018e7f4a-bbbb-7abc-8def-00000000000b",
  "name": "New Corp",
  "slug": "new-corp",
  "createdAt": "2025-01-15T12:00:00Z"
}
```

---

### PATCH /api/admin/tenants/{tenantId}

Update tenant configuration.

**Request Body** – Partial update, any fields from tenant settings.

**Response 200 OK** – Updated tenant object.

---

*Last updated: 2025-01-15 | API version: 1.0.0*
