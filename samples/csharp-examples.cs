// Auth Framework – C# HttpClient flow examples
// Requires .NET 9, top-level statements.
// Install: dotnet add package System.Net.Http.Json

using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

var baseUrl  = "http://localhost:5000/api";
var tenantId = "018e7f4a-0000-7abc-8def-000000000000";

using var http = new HttpClient { BaseAddress = new Uri(baseUrl) };
http.DefaultRequestHeaders.Add("X-Tenant-ID", tenantId);

var json = new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase };

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 1 – Complete login flow: register → verify email → login → get profile
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("=== FLOW 1: Register → Login → Profile ===");

// Step 1a: Register a new user
var registerBody = new
{
    email            = "jane.doe@example.com",
    password         = "S3cure!Pass#2025",
    firstName        = "Jane",
    lastName         = "Doe",
    locale           = "en-US",
    timezone         = "America/New_York",
    consentToTerms   = true,
    consentToMarketing = false
};

var registerResp = await http.PostAsJsonAsync("/auth/register", registerBody);
registerResp.EnsureSuccessStatusCode();
var registerResult = await registerResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"Registered userId: {registerResult.GetProperty("userId")}");

// Step 1b: Verify email using the token from the registration email
//          (In practice the token comes from the email link query string)
var verifyBody = new { token = "verify.email.PLACEHOLDER_FROM_EMAIL" };
var verifyResp = await http.PostAsJsonAsync("/auth/verify-email", verifyBody);
verifyResp.EnsureSuccessStatusCode();
var verifyResult = await verifyResp.Content.ReadFromJsonAsync<JsonElement>();
var accessToken  = verifyResult.GetProperty("accessToken").GetString()!;
Console.WriteLine("Email verified – received access token.");

// Step 1c: Log in with credentials
var loginBody = new
{
    email        = "jane.doe@example.com",
    password     = "S3cure!Pass#2025",
    deviceName   = "CSharp-Client"
};

var loginResp = await http.PostAsJsonAsync("/auth/login", loginBody);
loginResp.EnsureSuccessStatusCode();
var loginResult  = await loginResp.Content.ReadFromJsonAsync<JsonElement>();
accessToken      = loginResult.GetProperty("accessToken").GetString()!;
var refreshToken = loginResult.GetProperty("refreshToken").GetString()!;
Console.WriteLine("Logged in successfully.");

// Step 1d: Fetch the user's profile using the access token
http.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", accessToken);

var profileResp = await http.GetAsync("/users/me");
profileResp.EnsureSuccessStatusCode();
var profile = await profileResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"Profile: {profile.GetProperty("email")} – {profile.GetProperty("firstName")} {profile.GetProperty("lastName")}");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 2 – MFA enrollment: enable TOTP → get QR code → verify code
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 2: MFA Enrollment ===");

// Step 2a: Begin TOTP enrollment
var enrollBody = new { method = "totp", deviceName = "My Authenticator App" };
var enrollResp = await http.PostAsJsonAsync("/mfa/enroll", enrollBody);
enrollResp.EnsureSuccessStatusCode();
var enrollResult = await enrollResp.Content.ReadFromJsonAsync<JsonElement>();

var enrollmentId = enrollResult.GetProperty("enrollmentId").GetString()!;
var secret       = enrollResult.GetProperty("secret").GetString()!;
var qrCodeUri    = enrollResult.GetProperty("qrCodeUri").GetString()!;
var backupCodes  = enrollResult.GetProperty("backupCodes");

Console.WriteLine($"Enrollment ID : {enrollmentId}");
Console.WriteLine($"TOTP Secret   : {secret}");
Console.WriteLine($"QR Code URI   : {qrCodeUri}");
Console.WriteLine($"Backup Codes  : {backupCodes}");
Console.WriteLine("→ Scan the QR code in an authenticator app, then enter the 6-digit code.");

// Step 2b: Confirm enrollment with the TOTP code from the authenticator app
//          Replace "123456" with the actual code from the authenticator.
var verifyMfaBody = new { enrollmentId, code = "123456" };
var verifyMfaResp = await http.PostAsJsonAsync("/mfa/verify", verifyMfaBody);
verifyMfaResp.EnsureSuccessStatusCode();
var verifyMfaResult = await verifyMfaResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"MFA enrolled: deviceId={verifyMfaResult.GetProperty("deviceId")}");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 3 – OAuth authorization code flow with PKCE
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 3: OAuth 2.0 Authorization Code + PKCE ===");

// Step 3a: Register an OAuth application
var appBody = new
{
    name             = "My Web App",
    redirectUris     = new[] { "https://myapp.example.com/callback" },
    scopes           = new[] { "openid", "profile", "email" },
    applicationType  = "web",
    grantTypes       = new[] { "authorization_code", "refresh_token" }
};

var appResp = await http.PostAsJsonAsync("/oauth/applications", appBody);
appResp.EnsureSuccessStatusCode();
var appResult    = await appResp.Content.ReadFromJsonAsync<JsonElement>();
var clientId     = appResult.GetProperty("clientId").GetString()!;
var clientSecret = appResult.GetProperty("clientSecret").GetString()!;
Console.WriteLine($"OAuth App created – clientId: {clientId}");
Console.WriteLine("⚠  Store the clientSecret now – it will not be shown again.");

// Step 3b: Generate PKCE code_verifier and code_challenge (S256)
var codeVerifierBytes = RandomNumberGenerator.GetBytes(32);
var codeVerifier      = Base64UrlEncode(codeVerifierBytes);
var challengeBytes    = SHA256.HashData(Encoding.ASCII.GetBytes(codeVerifier));
var codeChallenge     = Base64UrlEncode(challengeBytes);
var state             = Base64UrlEncode(RandomNumberGenerator.GetBytes(16));

// Step 3c: Build the authorization URL and redirect the browser
var authorizeUrl =
    $"{baseUrl}/oauth/authorize" +
    $"?response_type=code" +
    $"&client_id={Uri.EscapeDataString(clientId)}" +
    $"&redirect_uri={Uri.EscapeDataString("https://myapp.example.com/callback")}" +
    $"&scope={Uri.EscapeDataString("openid profile email")}" +
    $"&state={state}" +
    $"&code_challenge={codeChallenge}" +
    $"&code_challenge_method=S256";

Console.WriteLine($"Redirect browser to:\n{authorizeUrl}");

// Step 3d: Exchange the authorization code for tokens
//          The auth code arrives via the redirect_uri callback.
var authCode = "authcode.PLACEHOLDER_FROM_CALLBACK";
var tokenContent = new FormUrlEncodedContent(new Dictionary<string, string>
{
    ["grant_type"]    = "authorization_code",
    ["code"]          = authCode,
    ["redirect_uri"]  = "https://myapp.example.com/callback",
    ["client_id"]     = clientId,
    ["client_secret"] = clientSecret,
    ["code_verifier"] = codeVerifier
});

var tokenResp = await http.PostAsync("/oauth/token", tokenContent);
tokenResp.EnsureSuccessStatusCode();
var tokenResult = await tokenResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"OAuth access token: {tokenResult.GetProperty("access_token").GetString()?[..20]}...");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 4 – SAML SSO flow (SP-initiated)
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 4: SAML SSO Flow ===");

// Step 4a: List available SSO providers for the tenant
// Remove auth header for this public endpoint
http.DefaultRequestHeaders.Authorization = null;
var providersResp = await http.GetAsync("/sso/providers");
providersResp.EnsureSuccessStatusCode();
var providers = await providersResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"SSO Providers: {providers.GetProperty("providers")}");

// Step 4b: Initiate SSO login – redirect the user's browser to the IdP
var ssoState     = Base64UrlEncode(RandomNumberGenerator.GetBytes(16));
var ssoLoginUrl  = $"{baseUrl}/sso/login/corporate-saml?state={ssoState}&redirect_uri=/dashboard";
Console.WriteLine($"Redirect browser to IdP: {ssoLoginUrl}");

// Step 4c: After SAML assertion callback, the API sets a session automatically.
//          The browser is redirected to the application with a session cookie
//          or an authorization code (depending on configuration).
Console.WriteLine("After callback, exchange code or use session cookie from redirect.");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 5 – GDPR data export
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 5: GDPR Data Export ===");

// Restore access token
http.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", accessToken);

// Step 5a: Request a data export
var exportResp = await http.GetAsync("/users/me/data-export");
exportResp.EnsureSuccessStatusCode();
var exportResult = await exportResp.Content.ReadFromJsonAsync<JsonElement>();
var exportId     = exportResult.GetProperty("exportId").GetString()!;
Console.WriteLine($"Export requested – exportId: {exportId}");
Console.WriteLine($"Status: {exportResult.GetProperty("status")}");
Console.WriteLine($"Estimated completion: {exportResult.GetProperty("estimatedCompletionTime")}");
Console.WriteLine("→ A secure download link will be sent to the verified email address.");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 6 – GDPR account deletion (right to erasure)
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 6: GDPR Account Deletion ===");

var deleteBody = new
{
    reason        = "No longer using the service",
    confirmEmail  = "jane.doe@example.com",
    password      = "S3cure!Pass#2025"
};

var deleteResp = await http.PostAsJsonAsync("/users/me/delete", deleteBody);
deleteResp.EnsureSuccessStatusCode();
var deleteResult = await deleteResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine($"Deletion scheduled for: {deleteResult.GetProperty("deletionScheduledAt")}");
Console.WriteLine($"Cancellation deadline : {deleteResult.GetProperty("cancellationDeadline")}");

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 7 – Refresh token flow
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 7: Refresh Token Flow ===");

// Step 7a: Use the refresh token to obtain a new access token
http.DefaultRequestHeaders.Authorization = null; // Refresh does not need a Bearer token

var refreshBody = new { refreshToken };
var refreshResp = await http.PostAsJsonAsync("/auth/refresh-token", refreshBody);
refreshResp.EnsureSuccessStatusCode();
var refreshResult = await refreshResp.Content.ReadFromJsonAsync<JsonElement>();

// The old refresh token is now invalid; use the new ones
accessToken  = refreshResult.GetProperty("accessToken").GetString()!;
refreshToken = refreshResult.GetProperty("refreshToken").GetString()!;
Console.WriteLine("Tokens rotated successfully.");
Console.WriteLine($"New access token (preview): {accessToken[..20]}...");

// Restore new access token for subsequent requests
http.DefaultRequestHeaders.Authorization =
    new AuthenticationHeaderValue("Bearer", accessToken);

// ─────────────────────────────────────────────────────────────────────────────
// FLOW 8 – Password reset flow
// ─────────────────────────────────────────────────────────────────────────────
Console.WriteLine("\n=== FLOW 8: Password Reset Flow ===");

// Step 8a: Request a password reset email
http.DefaultRequestHeaders.Authorization = null;

var resetRequestBody = new { email = "jane.doe@example.com" };
var resetRequestResp = await http.PostAsJsonAsync("/auth/password-reset", resetRequestBody);
resetRequestResp.EnsureSuccessStatusCode();
var resetRequestResult = await resetRequestResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine(resetRequestResult.GetProperty("message").GetString());

// Step 8b: Confirm the password reset with the token from the email link
var resetConfirmBody = new
{
    token       = "reset.token.PLACEHOLDER_FROM_EMAIL",
    newPassword = "N3wS3cure!Pass#2025"
};

var resetConfirmResp = await http.PostAsJsonAsync("/auth/password-reset/confirm", resetConfirmBody);
resetConfirmResp.EnsureSuccessStatusCode();
var resetConfirmResult = await resetConfirmResp.Content.ReadFromJsonAsync<JsonElement>();
Console.WriteLine(resetConfirmResult.GetProperty("message").GetString());

// ─────────────────────────────────────────────────────────────────────────────
// Helper: Base64Url encode (no padding, URL-safe)
// ─────────────────────────────────────────────────────────────────────────────
static string Base64UrlEncode(byte[] input) =>
    Convert.ToBase64String(input)
        .Replace('+', '-')
        .Replace('/', '_')
        .TrimEnd('=');
