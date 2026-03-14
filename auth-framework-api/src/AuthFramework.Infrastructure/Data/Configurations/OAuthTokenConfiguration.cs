using AuthFramework.Core.Entities;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;

namespace AuthFramework.Infrastructure.Data.Configurations;

internal sealed class OAuthTokenConfiguration : IEntityTypeConfiguration<OAuthToken>
{
    public void Configure(EntityTypeBuilder<OAuthToken> builder)
    {
        builder.HasKey(t => t.Id);

        builder.Property(t => t.AccessToken)
            .IsRequired()
            .HasMaxLength(4096);

        builder.Property(t => t.RefreshToken)
            .HasMaxLength(512);

        builder.Property(t => t.Scopes)
            .HasColumnType("text[]");

        builder.HasIndex(t => t.AccessToken)
            .IsUnique()
            .HasDatabaseName("ix_oauth_tokens_access_token");

        builder.HasIndex(t => new { t.ApplicationId, t.TenantId })
            .HasDatabaseName("ix_oauth_tokens_app_tenant");

        builder.HasOne(t => t.Application)
            .WithMany(a => a.Tokens)
            .HasForeignKey(t => t.ApplicationId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}
