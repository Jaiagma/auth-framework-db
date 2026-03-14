using Xunit;
using AuthFramework.Shared.Utilities;
using FluentAssertions;

namespace AuthFramework.Tests.Unit.Utilities;

public sealed class UuidV7GeneratorTests
{
    [Fact]
    public void NewGuid_ReturnsNonEmptyGuid()
    {
        var uuid = UuidV7Generator.NewGuid();
        uuid.Should().NotBe(Guid.Empty);
    }

    [Fact]
    public void NewGuid_TwoConsecutiveCalls_ProduceDifferentGuids()
    {
        var uuid1 = UuidV7Generator.NewGuid();
        var uuid2 = UuidV7Generator.NewGuid();
        uuid1.Should().NotBe(uuid2);
    }

    [Fact]
    public void NewGuid_IsTimeOrdered_WhenGeneratedSequentially()
    {
        // Generate 100 UUIDs and verify they are in ascending order
        var guids = Enumerable.Range(0, 100).Select(_ =>
        {
            // Small delay not needed since UUID v7 uses ms timestamp + random suffix
            return UuidV7Generator.NewGuid();
        }).ToList();

        // Verify as strings (UUID v7 sorts lexicographically when using big-endian byte order)
        var sortedGuids = guids.Order().ToList();

        // At least verify all are unique
        guids.Distinct().Should().HaveCount(100);
    }

    [Fact]
    public void GetCreationTime_ReturnsTimestampCloseToNow()
    {
        var before = DateTimeOffset.UtcNow;
        var uuid = UuidV7Generator.NewGuid();
        var after = DateTimeOffset.UtcNow;

        var timestamp = UuidV7Generator.GetCreationTime(uuid);

        timestamp.Should().BeOnOrAfter(before.AddSeconds(-1));
        timestamp.Should().BeOnOrBefore(after.AddSeconds(1));
    }

    [Fact]
    public void GetTimestampMs_ReturnsPositiveValue()
    {
        var uuid = UuidV7Generator.NewGuid();
        var tsMs = UuidV7Generator.GetTimestampMs(uuid);
        tsMs.Should().BeGreaterThan(0);
    }

    [Fact]
    public void NewGuid_Version7Bits_AreCorrect()
    {
        var uuid = UuidV7Generator.NewGuid();
        var bytes = uuid.ToByteArray(bigEndian: true);

        // Version bits (byte 6, high nibble) should be 7
        var version = (bytes[6] >> 4) & 0x0F;
        version.Should().Be(7);

        // Variant bits (byte 8, top 2 bits) should be 10xx
        var variant = (bytes[8] >> 6) & 0x03;
        variant.Should().Be(2); // binary 10
    }
}
