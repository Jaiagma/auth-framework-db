using AuthFramework.Shared.Exceptions;
using AuthFramework.Shared.Utilities;
using FluentAssertions;
using Xunit;

namespace AuthFramework.Tests.Unit.Utilities;

public sealed class PasswordValidatorTests
{
    [Theory]
    [InlineData("P@ssw0rd!")]          // valid
    [InlineData("Str0ng!Passw0rd")]    // valid
    [InlineData("C0mpl3x#Password!")]  // valid
    public void Validate_WithValidPassword_DoesNotThrow(string password)
    {
        var act = () => PasswordValidator.Validate(password);
        act.Should().NotThrow();
    }

    [Theory]
    [InlineData("short1!A")]    // exactly 8 chars - valid
    public void Validate_WithMinLengthPassword_DoesNotThrow(string password)
    {
        var act = () => PasswordValidator.Validate(password);
        act.Should().NotThrow();
    }

    [Theory]
    [InlineData("weak")]           // too short, no uppercase, no digit, no special
    [InlineData("alllowercase1!")] // no uppercase
    [InlineData("ALLUPPERCASE1!")] // no lowercase
    [InlineData("NoDigits!Here")]  // no digit
    [InlineData("NoSpecial1Char")] // no special char
    [InlineData("")]               // empty
    public void Validate_WithInvalidPassword_ThrowsValidationException(string password)
    {
        var act = () => PasswordValidator.Validate(password);
        act.Should().Throw<ValidationException>();
    }

    [Fact]
    public void Validate_WithNullPassword_ThrowsValidationException()
    {
        var act = () => PasswordValidator.Validate(null!);
        act.Should().Throw<ValidationException>();
    }

    [Fact]
    public void IsValid_WithValidPassword_ReturnsTrue()
    {
        PasswordValidator.IsValid("P@ssw0rd!").Should().BeTrue();
    }

    [Fact]
    public void IsValid_WithInvalidPassword_ReturnsFalse()
    {
        PasswordValidator.IsValid("weak").Should().BeFalse();
    }

    [Fact]
    public void Validate_ExceedingMaxLength_ThrowsValidationException()
    {
        var tooLong = "P@ssw0rd!" + new string('a', 200);
        var act = () => PasswordValidator.Validate(tooLong);
        act.Should().Throw<ValidationException>()
            .Which.Message.Should().Contain("exceed");
    }
}
