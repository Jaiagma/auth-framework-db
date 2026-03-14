using System.Security.Cryptography;
using System.Text;
using AuthFramework.Application.Interfaces;
using Microsoft.Extensions.Configuration;

namespace AuthFramework.Application.Services;

/// <summary>AES-256-GCM encryption and SHA-256 HMAC hashing for PII protection.</summary>
public sealed class EncryptionService : IEncryptionService
{
    private readonly byte[] _key;
    private readonly byte[] _hmacKey;

    public EncryptionService(IConfiguration configuration)
    {
        var keyBase64 = configuration["EncryptionSettings:Key"]
            ?? throw new InvalidOperationException("EncryptionSettings:Key is not configured.");
        var rawKey = Convert.FromBase64String(keyBase64);
        // Derive a 32-byte AES key and 32-byte HMAC key from the configured key
        using var sha = SHA256.Create();
        _key = sha.ComputeHash(rawKey);
        _hmacKey = SHA256.HashData(Encoding.UTF8.GetBytes("hmac:" + keyBase64));
    }

    /// <inheritdoc/>
    public string Encrypt(string plaintext)
    {
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);
        var nonce = new byte[AesGcm.NonceByteSizes.MaxSize]; // 12 bytes
        RandomNumberGenerator.Fill(nonce);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag = new byte[AesGcm.TagByteSizes.MaxSize]; // 16 bytes

        using var aes = new AesGcm(_key, AesGcm.TagByteSizes.MaxSize);
        aes.Encrypt(nonce, plaintextBytes, ciphertext, tag);

        // Format: nonce (12) || tag (16) || ciphertext
        var combined = new byte[nonce.Length + tag.Length + ciphertext.Length];
        Buffer.BlockCopy(nonce, 0, combined, 0, nonce.Length);
        Buffer.BlockCopy(tag, 0, combined, nonce.Length, tag.Length);
        Buffer.BlockCopy(ciphertext, 0, combined, nonce.Length + tag.Length, ciphertext.Length);

        return Convert.ToBase64String(combined);
    }

    /// <inheritdoc/>
    public string Decrypt(string ciphertext)
    {
        var combined = Convert.FromBase64String(ciphertext);
        const int nonceSize = 12;
        const int tagSize = 16;

        var nonce = combined[..nonceSize];
        var tag = combined[nonceSize..(nonceSize + tagSize)];
        var encryptedData = combined[(nonceSize + tagSize)..];
        var plaintext = new byte[encryptedData.Length];

        using var aes = new AesGcm(_key, AesGcm.TagByteSizes.MaxSize);
        aes.Decrypt(nonce, encryptedData, tag, plaintext);

        return Encoding.UTF8.GetString(plaintext);
    }

    /// <inheritdoc/>
    public string Hash(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value.ToLowerInvariant());
        var hash = HMACSHA256.HashData(_hmacKey, bytes);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    /// <inheritdoc/>
    public bool VerifyHash(string value, string hash)
        => string.Equals(Hash(value), hash, StringComparison.OrdinalIgnoreCase);
}
