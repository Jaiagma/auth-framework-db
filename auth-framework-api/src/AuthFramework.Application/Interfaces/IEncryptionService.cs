namespace AuthFramework.Application.Interfaces;

/// <summary>Service for encrypting, decrypting and hashing sensitive data.</summary>
public interface IEncryptionService
{
    /// <summary>Encrypts plaintext using AES-256-GCM. Returns a Base64-encoded ciphertext with nonce prepended.</summary>
    string Encrypt(string plaintext);

    /// <summary>Decrypts an AES-256-GCM ciphertext previously produced by <see cref="Encrypt"/>.</summary>
    string Decrypt(string ciphertext);

    /// <summary>Creates a deterministic SHA-256 HMAC hash suitable for indexed lookups (e.g., email hashing).</summary>
    string Hash(string value);

    /// <summary>Verifies that <paramref name="value"/> produces the given <paramref name="hash"/>.</summary>
    bool VerifyHash(string value, string hash);
}
