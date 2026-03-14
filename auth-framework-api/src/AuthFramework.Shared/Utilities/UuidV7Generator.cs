using System.Security.Cryptography;

namespace AuthFramework.Shared.Utilities;

/// <summary>
/// Generates UUID version 7 identifiers (time-ordered, RFC 9562).
/// UUID v7 embeds a Unix millisecond timestamp in the high bits, making UUIDs
/// naturally sortable by creation time — ideal for database primary keys.
/// </summary>
public static class UuidV7Generator
{
    /// <summary>Generates a new UUID v7.</summary>
    public static Guid NewGuid()
    {
        var bytes = new byte[16];
        RandomNumberGenerator.Fill(bytes);

        var timestampMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        // Embed 48-bit Unix timestamp in big-endian order in bytes 0-5
        bytes[0] = (byte)(timestampMs >> 40);
        bytes[1] = (byte)(timestampMs >> 32);
        bytes[2] = (byte)(timestampMs >> 24);
        bytes[3] = (byte)(timestampMs >> 16);
        bytes[4] = (byte)(timestampMs >> 8);
        bytes[5] = (byte)timestampMs;

        // Set version to 7 (bits 4-7 of byte 6)
        bytes[6] = (byte)((bytes[6] & 0x0F) | 0x70);

        // Set variant to 10xx (RFC 4122 / RFC 9562 variant)
        bytes[8] = (byte)((bytes[8] & 0x3F) | 0x80);

        return new Guid(bytes, bigEndian: true);
    }

    /// <summary>Extracts the Unix millisecond timestamp from a UUID v7.</summary>
    public static long GetTimestampMs(Guid uuid)
    {
        var bytes = uuid.ToByteArray(bigEndian: true);
        return ((long)bytes[0] << 40)
             | ((long)bytes[1] << 32)
             | ((long)bytes[2] << 24)
             | ((long)bytes[3] << 16)
             | ((long)bytes[4] << 8)
             | bytes[5];
    }

    /// <summary>Returns the <see cref="DateTimeOffset"/> embedded in a UUID v7.</summary>
    public static DateTimeOffset GetCreationTime(Guid uuid)
        => DateTimeOffset.FromUnixTimeMilliseconds(GetTimestampMs(uuid));
}
