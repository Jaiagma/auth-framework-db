namespace AuthFramework.Core.Enums;

/// <summary>Represents the lifecycle status of a user account.</summary>
public enum UserStatus
{
    Active = 1,
    Inactive = 2,
    Locked = 3,
    PendingVerification = 4,
    Suspended = 5,
    Deleted = 6
}
