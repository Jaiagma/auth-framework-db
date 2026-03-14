using AuthFramework.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AuthFramework.Infrastructure.Data.Configurations;

internal sealed class MfaDeviceConfiguration : IEntityTypeConfiguration<MfaDevice>
{
    public void Configure(EntityTypeBuilder<MfaDevice> builder)
    {
        builder.HasKey(d => d.Id);

        builder.Property(d => d.MethodType)
            .HasConversion<string>()
            .HasMaxLength(50)
            .IsRequired();

        builder.Property(d => d.Name).HasMaxLength(100);
        builder.Property(d => d.SecretKey).HasMaxLength(512);
        builder.Property(d => d.PhoneNumber).HasMaxLength(512);
        builder.Property(d => d.Email).HasMaxLength(256);

        builder.HasIndex(d => new { d.UserId, d.TenantId })
            .HasDatabaseName("ix_mfa_devices_user_tenant");

        builder.HasQueryFilter(d => d.IsActive);
    }
}
