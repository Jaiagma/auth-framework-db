using System.Text.Json;
using AuthFramework.Shared.Exceptions;
using Microsoft.AspNetCore.Mvc;

namespace AuthFramework.Api.Middleware;

/// <summary>Global exception handler that converts exceptions to RFC 7807 Problem Details responses.</summary>
public sealed class ExceptionHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ExceptionHandlingMiddleware> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    public ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        var (statusCode, errorCode, title) = exception switch
        {
            AuthenticationException => (StatusCodes.Status401Unauthorized, "AUTHENTICATION_FAILED", "Authentication failed"),
            AccountLockedException => (StatusCodes.Status423Locked, "ACCOUNT_LOCKED", "Account locked"),
            MfaRequiredException => (StatusCodes.Status403Forbidden, "MFA_REQUIRED", "MFA required"),
            TenantNotFoundException => (StatusCodes.Status404NotFound, "TENANT_NOT_FOUND", "Tenant not found"),
            UserNotFoundException => (StatusCodes.Status404NotFound, "USER_NOT_FOUND", "User not found"),
            InvalidTokenException => (StatusCodes.Status401Unauthorized, "INVALID_TOKEN", "Invalid token"),
            ValidationException => (StatusCodes.Status422UnprocessableEntity, "VALIDATION_ERROR", "Validation failed"),
            AuthFrameworkException e => (StatusCodes.Status400BadRequest, e.ErrorCode, "Request error"),
            UnauthorizedAccessException => (StatusCodes.Status403Forbidden, "FORBIDDEN", "Forbidden"),
            NotImplementedException => (StatusCodes.Status501NotImplemented, "NOT_IMPLEMENTED", "Not implemented"),
            _ => (StatusCodes.Status500InternalServerError, "INTERNAL_ERROR", "An unexpected error occurred"),
        };

        if (statusCode >= 500)
            _logger.LogError(exception, "Unhandled exception for {Method} {Path}", context.Request.Method, context.Request.Path);
        else
            _logger.LogWarning(exception, "Handled exception {ErrorCode} for {Method} {Path}", errorCode, context.Request.Method, context.Request.Path);

        var problem = new ProblemDetails
        {
            Status = statusCode,
            Title = title,
            Detail = exception.Message,
            Instance = context.Request.Path,
            Extensions = { ["errorCode"] = errorCode },
        };

        if (context.Items.TryGetValue("CorrelationId", out var correlationId))
            problem.Extensions["correlationId"] = correlationId;

        if (exception is ValidationException validationEx)
            problem.Extensions["errors"] = validationEx.Errors;

        if (exception is AccountLockedException lockedException)
            problem.Extensions["lockedUntil"] = lockedException.LockedUntil;

        if (exception is MfaRequiredException mfaEx && mfaEx.ChallengeId.HasValue)
            problem.Extensions["challengeId"] = mfaEx.ChallengeId.Value;

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/problem+json";

        await context.Response.WriteAsync(JsonSerializer.Serialize(problem, JsonOptions));
    }
}
