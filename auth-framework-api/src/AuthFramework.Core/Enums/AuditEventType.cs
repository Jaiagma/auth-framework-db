namespace AuthFramework.Core.Enums;

/// <summary>Categories for audit log events.</summary>
public enum AuditEventType
{
    Authentication = 1,
    Authorization = 2,
    UserManagement = 3,
    DataAccess = 4,
    Security = 5,
    Compliance = 6,
    System = 7
}
