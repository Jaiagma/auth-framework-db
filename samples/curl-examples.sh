#!/usr/bin/env bash
# cURL examples for the Auth Framework API
# Replace placeholder values before use.

BASE_URL="http://localhost:5000/api"
TENANT_ID="018e7f4a-0000-7abc-8def-000000000000"
ACCESS_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.PLACEHOLDER"
REFRESH_TOKEN="v2.refresh.PLACEHOLDER"
MFA_TOKEN="mfa.intermediate.PLACEHOLDER"
ADMIN_TOKEN="eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.ADMIN_PLACEHOLDER"

echo "=== Auth Framework API – cURL Examples ==="

# ---------------------------------------------------------------------------
# 1. Register user
# ---------------------------------------------------------------------------
echo -e "\n--- 1. Register user ---"
curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d '{
    "email": "jane.doe@example.com",
    "password": "S3cure!Pass#2025",
    "firstName": "Jane",
    "lastName": "Doe",
    "locale": "en-US",
    "timezone": "America/New_York",
    "consentToTerms": true,
    "consentToMarketing": false
  }' | jq .

# ---------------------------------------------------------------------------
# 2. Login (no MFA)
# ---------------------------------------------------------------------------
echo -e "\n--- 2. Login ---"
curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d '{
    "email": "jane.doe@example.com",
    "password": "S3cure!Pass#2025",
    "deviceName": "curl-client"
  }' | jq .

# ---------------------------------------------------------------------------
# 3. Login with MFA (two-step)
# ---------------------------------------------------------------------------
echo -e "\n--- 3a. Login (triggers MFA) ---"
MFA_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/login" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d '{
    "email": "jane.doe@example.com",
    "password": "S3cure!Pass#2025"
  }')
echo "$MFA_RESPONSE" | jq .
MFA_TOKEN=$(echo "$MFA_RESPONSE" | jq -r '.mfaToken')

echo -e "\n--- 3b. Complete MFA challenge ---"
curl -s -X POST "$BASE_URL/mfa/verify" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d "{
    \"mfaToken\": \"$MFA_TOKEN\",
    \"code\": \"123456\",
    \"method\": \"totp\"
  }" | jq .

# ---------------------------------------------------------------------------
# 4. Refresh token
# ---------------------------------------------------------------------------
echo -e "\n--- 4. Refresh token ---"
curl -s -X POST "$BASE_URL/auth/refresh-token" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d "{\"refreshToken\": \"$REFRESH_TOKEN\"}" | jq .

# ---------------------------------------------------------------------------
# 5. Logout
# ---------------------------------------------------------------------------
echo -e "\n--- 5. Logout ---"
curl -s -X POST "$BASE_URL/auth/logout" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "{\"refreshToken\": \"$REFRESH_TOKEN\", \"allSessions\": false}" \
  -o /dev/null -w "HTTP %{http_code}\n"

# ---------------------------------------------------------------------------
# 6. Password reset request
# ---------------------------------------------------------------------------
echo -e "\n--- 6. Password reset request ---"
curl -s -X POST "$BASE_URL/auth/password-reset" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d '{"email": "jane.doe@example.com"}' | jq .

# ---------------------------------------------------------------------------
# 7. Verify email
# ---------------------------------------------------------------------------
echo -e "\n--- 7. Verify email ---"
curl -s -X POST "$BASE_URL/auth/verify-email" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -d '{"token": "verify.email.PLACEHOLDER_TOKEN"}' | jq .

# ---------------------------------------------------------------------------
# 8. Enroll TOTP MFA
# ---------------------------------------------------------------------------
echo -e "\n--- 8. Enroll TOTP MFA ---"
ENROLL_RESPONSE=$(curl -s -X POST "$BASE_URL/mfa/enroll" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{"method": "totp", "deviceName": "My Authenticator App"}')
echo "$ENROLL_RESPONSE" | jq .
ENROLLMENT_ID=$(echo "$ENROLL_RESPONSE" | jq -r '.enrollmentId')

# ---------------------------------------------------------------------------
# 9. Verify MFA enrollment (confirm device)
# ---------------------------------------------------------------------------
echo -e "\n--- 9. Verify MFA enrollment ---"
curl -s -X POST "$BASE_URL/mfa/verify" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d "{
    \"enrollmentId\": \"$ENROLLMENT_ID\",
    \"code\": \"123456\"
  }" | jq .

# ---------------------------------------------------------------------------
# 10. List MFA devices
# ---------------------------------------------------------------------------
echo -e "\n--- 10. List MFA devices ---"
curl -s -X GET "$BASE_URL/mfa/devices" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

# ---------------------------------------------------------------------------
# 11. OAuth application creation
# ---------------------------------------------------------------------------
echo -e "\n--- 11. Create OAuth application ---"
OAUTH_APP=$(curl -s -X POST "$BASE_URL/oauth/applications" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "name": "My Web App",
    "redirectUris": ["https://myapp.example.com/callback"],
    "scopes": ["openid", "profile", "email"],
    "applicationType": "web",
    "grantTypes": ["authorization_code", "refresh_token"]
  }')
echo "$OAUTH_APP" | jq .
CLIENT_ID=$(echo "$OAUTH_APP" | jq -r '.clientId')

# ---------------------------------------------------------------------------
# 12. OAuth authorize redirect (browser flow – show URL only)
# ---------------------------------------------------------------------------
echo -e "\n--- 12. OAuth authorize URL (open in browser) ---"
CODE_VERIFIER="dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
CODE_CHALLENGE=$(echo -n "$CODE_VERIFIER" | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '=')
STATE="random-csrf-state-$(date +%s)"
echo "$BASE_URL/oauth/authorize?response_type=code&client_id=$CLIENT_ID&redirect_uri=https%3A%2F%2Fmyapp.example.com%2Fcallback&scope=openid%20profile%20email&state=$STATE&code_challenge=$CODE_CHALLENGE&code_challenge_method=S256"

# ---------------------------------------------------------------------------
# 13. OAuth token exchange (authorization code → tokens)
# ---------------------------------------------------------------------------
echo -e "\n--- 13. OAuth token exchange ---"
curl -s -X POST "$BASE_URL/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "X-Tenant-ID: $TENANT_ID" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "code=authcode.PLACEHOLDER" \
  --data-urlencode "redirect_uri=https://myapp.example.com/callback" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=cs_live_PLACEHOLDER" \
  --data-urlencode "code_verifier=$CODE_VERIFIER" | jq .

# ---------------------------------------------------------------------------
# 14. OAuth token revoke
# ---------------------------------------------------------------------------
echo -e "\n--- 14. OAuth token revoke ---"
curl -s -X POST "$BASE_URL/oauth/revoke" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "X-Tenant-ID: $TENANT_ID" \
  --data-urlencode "token=$REFRESH_TOKEN" \
  --data-urlencode "token_type_hint=refresh_token" \
  --data-urlencode "client_id=$CLIENT_ID" \
  --data-urlencode "client_secret=cs_live_PLACEHOLDER" | jq .

# ---------------------------------------------------------------------------
# 15. Get user profile
# ---------------------------------------------------------------------------
echo -e "\n--- 15. Get user profile ---"
curl -s -X GET "$BASE_URL/users/me" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

# ---------------------------------------------------------------------------
# 16. Update user profile
# ---------------------------------------------------------------------------
echo -e "\n--- 16. Update user profile ---"
curl -s -X PATCH "$BASE_URL/users/me" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "firstName": "Jane",
    "lastName": "Smith",
    "locale": "en-GB",
    "timezone": "Europe/London"
  }' | jq .

# ---------------------------------------------------------------------------
# 17. List sessions
# ---------------------------------------------------------------------------
echo -e "\n--- 17. List sessions ---"
curl -s -X GET "$BASE_URL/users/me/sessions" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

# ---------------------------------------------------------------------------
# 18. Revoke session
# ---------------------------------------------------------------------------
echo -e "\n--- 18. Revoke session ---"
SESSION_ID="018e7f4a-2222-7abc-8def-000000000002"
curl -s -X DELETE "$BASE_URL/users/me/sessions/$SESSION_ID" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -o /dev/null -w "HTTP %{http_code}\n"

# ---------------------------------------------------------------------------
# 19. SSO provider list
# ---------------------------------------------------------------------------
echo -e "\n--- 19. List SSO providers ---"
curl -s -X GET "$BASE_URL/sso/providers" \
  -H "X-Tenant-ID: $TENANT_ID" | jq .

# ---------------------------------------------------------------------------
# 20. Export user data (GDPR Article 20)
# ---------------------------------------------------------------------------
echo -e "\n--- 20. Request GDPR data export ---"
curl -s -X GET "$BASE_URL/users/me/data-export" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" | jq .

# ---------------------------------------------------------------------------
# 21. Request account deletion (GDPR Article 17)
# ---------------------------------------------------------------------------
echo -e "\n--- 21. Request account deletion ---"
curl -s -X POST "$BASE_URL/users/me/delete" \
  -H "Content-Type: application/json" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -d '{
    "reason": "No longer using the service",
    "confirmEmail": "jane.doe@example.com",
    "password": "S3cure!Pass#2025"
  }' | jq .

# ---------------------------------------------------------------------------
# 22. Admin – list users
# ---------------------------------------------------------------------------
echo -e "\n--- 22. Admin: list users ---"
curl -s -X GET "$BASE_URL/admin/users?page=1&pageSize=20&status=active" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .

# ---------------------------------------------------------------------------
# 23. Admin – get audit logs
# ---------------------------------------------------------------------------
echo -e "\n--- 23. Admin: get audit logs ---"
curl -s -X GET "$BASE_URL/admin/audit-logs?page=1&pageSize=50&from=2025-01-01T00:00:00Z" \
  -H "X-Tenant-ID: $TENANT_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq .
