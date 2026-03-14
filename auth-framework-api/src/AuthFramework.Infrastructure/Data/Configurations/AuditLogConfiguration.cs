using AuthFramework.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AuthFramework.Infrastructure.Data.Configurations;

internal sealed class AuditLogConfiguration : IEntityTypeConfiguration<AuditLog>
{
    public void Configure(EntityTypeBuilder<AuditLog> builder)
    {
        builder.HasKey(a => a.Id);
        builder.ToTable("audit_logs");

        builder.Property(a => a.EventType)
            .HasConversion<string>()
            .HasMaxLength(50)
            .IsRequired();

        builder.Property(a => a.Action)
            .IsRequired()
            .HasMaxLength(200);

        builder.Property(a => a.Status).HasMaxLength(50);
        builder.Property(a => a.ResourceType).HasMaxLength(100);
        builder.Property(a => a.ResourceId).HasMaxLength(200);
        builder.Property(a => a.IpAddress).HasMaxLength(45);
        builder.Property(a => a.UserAgent).HasMaxLength(1024);

        builder.Property(a => a.Details)
            .HasColumnType("jsonb");

        builder.HasIndex(a => new { a.TenantId, a.CreatedAt })
            .HasDatabaseName("ix_audit_logs_tenant_created");

        builder.HasIndex(a => a.UserId)
            .HasDatabaseName("ix_audit_logs_user_id");

        // Audit logs are immutable - no update operations
    }
}
