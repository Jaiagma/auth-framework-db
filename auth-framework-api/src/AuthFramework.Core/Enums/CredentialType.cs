namespace AuthFramework.Core.Enums;

/// <summary>Types of authentication credentials a user may have.</summary>
public enum CredentialType
{
    Password = 1,
    Passkey = 2,
    MagicLink = 3,
    Certificate = 4
}
