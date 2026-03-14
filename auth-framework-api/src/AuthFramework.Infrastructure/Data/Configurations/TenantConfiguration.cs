using AuthFramework.Core.Entities;
using AuthFramework.Core.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AuthFramework.Infrastructure.Data.Configurations;

internal sealed class TenantConfiguration : IEntityTypeConfiguration<Tenant>
{
    public void Configure(EntityTypeBuilder<Tenant> builder)
    {
        builder.HasKey(t => t.Id);

        builder.Property(t => t.Name)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(t => t.Slug)
            .IsRequired()
            .HasMaxLength(100);

        builder.Property(t => t.DisplayName)
            .HasMaxLength(200);

        builder.Property(t => t.LogoUrl)
            .HasMaxLength(2048);

        builder.Property(t => t.Status)
            .HasConversion<string>()
            .HasMaxLength(50)
            .IsRequired();

        builder.Property(t => t.Plan)
            .HasMaxLength(50);

        builder.Property(t => t.DataResidency)
            .HasMaxLength(50);

        builder.Property(t => t.AllowedMfaMethods)
            .HasColumnType("text[]");

        builder.Property(t => t.Metadata)
            .HasColumnType("jsonb");

        builder.HasIndex(t => t.Slug)
            .IsUnique()
            .HasDatabaseName("ix_tenants_slug");

        builder.HasIndex(t => t.Name)
            .IsUnique()
            .HasDatabaseName("ix_tenants_name");

        builder.HasQueryFilter(t => t.DeletedAt == null);
    }
}
