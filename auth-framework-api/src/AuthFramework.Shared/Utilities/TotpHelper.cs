using System.Security.Cryptography;
using System.Text;

namespace AuthFramework.Shared.Utilities;

/// <summary>
/// TOTP (Time-based One-Time Password) helper implementing RFC 6238.
/// Uses HMAC-SHA1 with a 30-second time step and 6-digit codes.
/// </summary>
public static class TotpHelper
{
    private const int Digits = 6;
    private const int TimeStepSeconds = 30;
    private const int AllowedDrift = 1; // windows allowed before/after current

    private static readonly char[] Base32Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".ToCharArray();

    /// <summary>Generates a TOTP code for the current time window.</summary>
    /// <param name="base32Secret">The base-32 encoded TOTP secret.</param>
    public static string GenerateCode(string base32Secret)
    {
        var key = FromBase32(base32Secret);
        var counter = GetTimeCounter(DateTimeOffset.UtcNow);
        return ComputeTotp(key, counter);
    }

    /// <summary>
    /// Verifies a TOTP code, allowing for clock drift of ±<see cref="AllowedDrift"/> time windows.
    /// </summary>
    public static bool VerifyCode(string base32Secret, string code)
    {
        if (string.IsNullOrWhiteSpace(code) || code.Length != Digits) return false;

        var key = FromBase32(base32Secret);
        var currentCounter = GetTimeCounter(DateTimeOffset.UtcNow);

        for (var drift = -AllowedDrift; drift <= AllowedDrift; drift++)
        {
            var expected = ComputeTotp(key, currentCounter + drift);
            if (string.Equals(expected, code, StringComparison.Ordinal))
                return true;
        }

        return false;
    }

    /// <summary>Generates a QR code URI for authenticator apps (otpauth:// scheme).</summary>
    public static string GenerateQrCodeUri(string issuer, string accountName, string base32Secret)
    {
        var encodedIssuer = Uri.EscapeDataString(issuer);
        var encodedAccount = Uri.EscapeDataString(accountName);
        return $"otpauth://totp/{encodedIssuer}:{encodedAccount}?secret={base32Secret}&issuer={encodedIssuer}&algorithm=SHA1&digits={Digits}&period={TimeStepSeconds}";
    }

    /// <summary>Encodes a byte array to a Base32 string.</summary>
    public static string ToBase32(byte[] data)
    {
        var result = new StringBuilder((data.Length * 8 + 4) / 5);
        var buffer = 0;
        var bitsLeft = 0;

        foreach (var b in data)
        {
            buffer = (buffer << 8) | b;
            bitsLeft += 8;
            while (bitsLeft >= 5)
            {
                bitsLeft -= 5;
                result.Append(Base32Alphabet[(buffer >> bitsLeft) & 0x1F]);
            }
        }

        if (bitsLeft > 0)
            result.Append(Base32Alphabet[(buffer << (5 - bitsLeft)) & 0x1F]);

        return result.ToString();
    }

    private static byte[] FromBase32(string base32)
    {
        base32 = base32.TrimEnd('=').ToUpperInvariant();
        var output = new byte[base32.Length * 5 / 8];
        var buffer = 0;
        var bitsLeft = 0;
        var index = 0;

        foreach (var c in base32)
        {
            var value = Array.IndexOf(Base32Alphabet, c);
            if (value < 0) continue;
            buffer = (buffer << 5) | value;
            bitsLeft += 5;
            if (bitsLeft >= 8)
            {
                bitsLeft -= 8;
                output[index++] = (byte)(buffer >> bitsLeft);
            }
        }

        return output[..index];
    }

    private static long GetTimeCounter(DateTimeOffset time)
        => time.ToUnixTimeSeconds() / TimeStepSeconds;

    private static string ComputeTotp(byte[] key, long counter)
    {
        var counterBytes = BitConverter.GetBytes(counter);
        if (BitConverter.IsLittleEndian) Array.Reverse(counterBytes);

        using var hmac = new HMACSHA1(key);
        var hash = hmac.ComputeHash(counterBytes);
        var offset = hash[^1] & 0x0F;
        var code = ((hash[offset] & 0x7F) << 24)
                 | ((hash[offset + 1] & 0xFF) << 16)
                 | ((hash[offset + 2] & 0xFF) << 8)
                 | (hash[offset + 3] & 0xFF);
        return (code % (int)Math.Pow(10, Digits)).ToString($"D{Digits}");
    }
}
