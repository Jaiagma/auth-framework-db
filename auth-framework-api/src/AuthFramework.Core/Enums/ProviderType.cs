namespace AuthFramework.Core.Enums;

/// <summary>Identity provider types for SSO and federation.</summary>
public enum ProviderType
{
    Google = 1,
    GitHub = 2,
    Microsoft = 3,
    Okta = 4,
    Auth0 = 5,
    Saml = 6,
    Oidc = 7,
    Custom = 8
}
