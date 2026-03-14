using AuthFramework.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AuthFramework.Infrastructure.Data.Configurations;

internal sealed class UserSessionConfiguration : IEntityTypeConfiguration<UserSession>
{
    public void Configure(EntityTypeBuilder<UserSession> builder)
    {
        builder.HasKey(s => s.Id);

        builder.Property(s => s.IpAddress).HasMaxLength(45);
        builder.Property(s => s.UserAgent).HasMaxLength(1024);

        builder.HasIndex(s => new { s.UserId, s.TenantId })
            .HasDatabaseName("ix_user_sessions_user_tenant");

        builder.HasIndex(s => s.ExpiresAt)
            .HasDatabaseName("ix_user_sessions_expires_at");

        builder.HasIndex(s => s.TenantId)
            .HasDatabaseName("ix_user_sessions_tenant_id");
    }
}
