namespace AuthFramework.Core.Enums;

/// <summary>Supported multi-factor authentication method types.</summary>
public enum MfaMethodType
{
    Totp = 1,
    Sms = 2,
    Email = 3,
    WebAuthn = 4,
    Push = 5
}
