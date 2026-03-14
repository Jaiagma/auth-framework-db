using System.Text;
using System.Text.RegularExpressions;

namespace AuthFramework.Shared.Extensions;

/// <summary>String utility extension methods.</summary>
public static partial class StringExtensions
{
    [GeneratedRegex(@"^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$")]
    private static partial Regex EmailRegex();

    [GeneratedRegex(@"[^a-z0-9\-]")]
    private static partial Regex SlugCleanupRegex();

    [GeneratedRegex(@"\-{2,}")]
    private static partial Regex MultiHyphenRegex();

    /// <summary>Returns true if the string is a valid email address format.</summary>
    public static bool IsValidEmail(this string? value)
        => !string.IsNullOrWhiteSpace(value) && EmailRegex().IsMatch(value);

    /// <summary>Converts a string to a URL-safe slug (lowercase, hyphens, no special chars).</summary>
    public static string ToSlug(this string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;

        var normalized = value.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder();

        foreach (var c in normalized)
        {
            var category = System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c);
            if (category == System.Globalization.UnicodeCategory.NonSpacingMark) continue;
            sb.Append(c);
        }

        var slug = sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
        slug = slug.Replace(' ', '-');
        slug = SlugCleanupRegex().Replace(slug, string.Empty);
        slug = MultiHyphenRegex().Replace(slug, "-");
        return slug.Trim('-');
    }

    /// <summary>Truncates a string to a maximum length, optionally appending an ellipsis.</summary>
    public static string Truncate(this string value, int maxLength, string suffix = "…")
    {
        if (string.IsNullOrEmpty(value) || value.Length <= maxLength) return value;
        return string.Concat(value.AsSpan(0, maxLength - suffix.Length), suffix);
    }

    /// <summary>Masks a string for logging (e.g., "user@example.com" -> "use***@example.com").</summary>
    public static string MaskEmail(this string email)
    {
        var atIndex = email.IndexOf('@');
        if (atIndex <= 2) return "***" + email[atIndex..];
        return email[..3] + new string('*', atIndex - 3) + email[atIndex..];
    }

    /// <summary>Returns true if the string is not null and not whitespace.</summary>
    public static bool HasValue(this string? value) => !string.IsNullOrWhiteSpace(value);
}
