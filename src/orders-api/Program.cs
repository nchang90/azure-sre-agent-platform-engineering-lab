using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.HttpOverrides;
using OpenTelemetry.Resources;
using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);

builder.Logging.AddSimpleConsole(options =>
{
    options.SingleLine = true;
    options.TimestampFormat = "yyyy-MM-ddTHH:mm:ss.fffZ ";
});

builder.Services.AddOpenApi();
if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services
        .AddOpenTelemetry()
        .UseAzureMonitor()
        .ConfigureResource(resource => resource.AddService("orders-api"));
}

builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
});

var app = builder.Build();

// S2 outage: the worker stays up so App Service routes traffic to it, but every
// route fails with 503. Crashing on startup instead leaves callers hanging until
// the container start times out, which shows up as timeouts rather than 5xx.
var chaosOutage = Environment.GetEnvironmentVariable("CHAOS_ENABLED") == "true" &&
    Environment.GetEnvironmentVariable("CHAOS_MODE") == "crash";

if (chaosOutage)
{
    app.Logger.LogCritical("CHAOS: orders-api is down (CHAOS_MODE=crash) — every request returns 503");
}

app.UseForwardedHeaders();

app.Use(async (context, next) =>
{
    var requestLogger = context.RequestServices
        .GetRequiredService<ILoggerFactory>()
        .CreateLogger("OrdersApi.Requests");
    var startedAt = DateTimeOffset.UtcNow;

    try
    {
        await next(context);
    }
    finally
    {
        var elapsedMs = (DateTimeOffset.UtcNow - startedAt).TotalMilliseconds;
        var statusCode = context.Response.StatusCode;
        var level = statusCode >= 500 ? LogLevel.Error : statusCode >= 400 ? LogLevel.Warning : LogLevel.Information;

        requestLogger.Log(level,
            "orders-api request {Method} {Path} completed with {StatusCode} in {ElapsedMs:F0}ms",
            context.Request.Method,
            context.Request.Path,
            statusCode,
            elapsedMs);
    }
});

if (chaosOutage)
{
    // Terminal: neither the website nor any endpoint runs, so /, /health, and /api/* all fail.
    app.Use(async (HttpContext context, RequestDelegate _) =>
    {
        context.RequestServices
            .GetRequiredService<ILoggerFactory>()
            .CreateLogger("OrdersApi.Chaos")
            .LogCritical("CHAOS: orders-api unavailable (CHAOS_MODE=crash), rejecting {Method} {Path}",
                context.Request.Method,
                context.Request.Path);
        context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;

        if (context.Request.Headers.Accept.ToString().Contains("text/html"))
        {
            context.Response.ContentType = "text/html; charset=utf-8";
            await context.Response.WriteAsync(
                "<!doctype html><title>Service unavailable</title>" +
                "<h1>503 Service Unavailable</h1><p>The Nordic Integration Summit site is down. Please try again later.</p>");
            return;
        }

        await context.Response.WriteAsJsonAsync(new { error = "orders-api unavailable", chaos = true, mode = "crash" });
    });
}
else if (Environment.GetEnvironmentVariable("CHAOS_ENABLED") == "true")
{
    app.UseMiddleware<ChaosMiddleware>();
    app.Logger.LogWarning("CHAOS MONKEY ENABLED — faults will be injected into requests");
}

// The Nordic Integration Summit website (wwwroot) sits behind the chaos middleware above,
// so it goes down together with the API.
app.UseDefaultFiles();
app.UseStaticFiles();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

var orders = new ConcurrentDictionary<string, OrderResult>();
var runtimeFailureRatePercent = 0;
var healthUnhealthy = false;

// Active ServiceNow Change Request the orders-api thinks it is currently running under.
// In a real system this is set by the deploy pipeline; here it's runtime-settable for demos.
var activeChangeRequest = Environment.GetEnvironmentVariable("ACTIVE_CR") ?? "";

app.MapGet("/api/info", () => Results.Ok(new
{
    service = "orders-api",
    version = "1.0.0",
    activeChangeRequest,
    message = "Orders API is running"
}));

app.MapGet("/health", (ILoggerFactory loggerFactory) =>
{
    var logger = loggerFactory.CreateLogger("OrdersApi.Health");
    if (healthUnhealthy)
    {
        logger.LogError("orders-api health check returning unhealthy");
        return Results.Problem(title: "unhealthy", statusCode: 503);
    }

    logger.LogInformation("orders-api health check returning healthy with active CR {ActiveChangeRequest}", activeChangeRequest);
    return Results.Ok(new { status = "healthy", service = "orders-api", activeChangeRequest });
});

app.MapPost("/api/orders", (OrderRequest request, IConfiguration config, ILoggerFactory loggerFactory) =>
{
    var logger = loggerFactory.CreateLogger("OrdersApi.Orders");
    if (request.Quantity <= 0)
    {
        logger.LogWarning("Rejected order for customer {CustomerId}: quantity {Quantity} is invalid", request.CustomerId, request.Quantity);
        return Results.BadRequest(new { error = "Quantity must be greater than zero" });
    }

    var configuredFailureRate = config.GetValue<int?>("Simulation:FailureRatePercent") ?? 0;
    var failureRate = runtimeFailureRatePercent > 0 ? runtimeFailureRatePercent : configuredFailureRate;
    var roll = Random.Shared.Next(1, 101);

    
    if (failureRate > 0 && roll <= failureRate)
    {
        logger.LogError(
            "Simulated order failure for customer {CustomerId}, sku {Sku}, failure rate {FailureRatePercent}, roll {Roll}, active CR {ActiveChangeRequest}",
            request.CustomerId,
            request.Sku,
            failureRate,
            roll,
            activeChangeRequest);
        return Results.Problem(
            title: "Order processing failed",
            detail: $"Simulated transient order failure during change {activeChangeRequest}",
            statusCode: StatusCodes.Status500InternalServerError);
    }

    var id = Guid.NewGuid().ToString("N");
    var result = new OrderResult(
        id,
        request.CustomerId,
        request.Sku,
        request.Quantity,
        "confirmed",
        activeChangeRequest,
        DateTimeOffset.UtcNow);

    orders[id] = result;
    logger.LogInformation("Created order {OrderId} for customer {CustomerId}, sku {Sku}, quantity {Quantity}", id, request.CustomerId, request.Sku, request.Quantity);
    return Results.Ok(result);
});

// Demo endpoint that always 500s — useful for quick alert-firing.
app.MapGet("/api/orders/fail", (ILoggerFactory loggerFactory) =>
{
    loggerFactory.CreateLogger("OrdersApi.Orders")
        .LogError("Forced order failure endpoint invoked with active CR {ActiveChangeRequest}", activeChangeRequest);
    return Results.Problem(
        title: "Order processing failed",
        detail: $"Forced failure (CR={activeChangeRequest})",
        statusCode: StatusCodes.Status500InternalServerError);
});

app.MapPost("/api/simulate/failure-rate/{percent:int}", (int percent, ILoggerFactory loggerFactory) =>
{
    if (percent < 0 || percent > 100)
    {
        loggerFactory.CreateLogger("OrdersApi.Simulation")
            .LogWarning("Rejected invalid simulated failure rate {FailureRatePercent}", percent);
        return Results.BadRequest(new { error = "Failure rate must be between 0 and 100" });
    }

    runtimeFailureRatePercent = percent;
    loggerFactory.CreateLogger("OrdersApi.Simulation")
        .LogWarning("Updated simulated failure rate to {FailureRatePercent}", runtimeFailureRatePercent);
    return Results.Ok(new
    {
        status = "updated",
        failureRatePercent = runtimeFailureRatePercent
    });
});

app.MapPost("/api/simulate/reset", (ILoggerFactory loggerFactory) =>
{
    runtimeFailureRatePercent = 0;
    loggerFactory.CreateLogger("OrdersApi.Simulation")
        .LogInformation("Reset simulated failure rate to 0");
    return Results.Ok(new
    {
        status = "reset",
        failureRatePercent = runtimeFailureRatePercent
    });
});

// Set the active CR at runtime (simulates deploy pipeline announcing a change window).
app.MapPost("/api/simulate/active-cr/{cr}", (string cr, ILoggerFactory loggerFactory) =>
{
    activeChangeRequest = cr;
    loggerFactory.CreateLogger("OrdersApi.Simulation")
        .LogInformation("Updated active change request to {ActiveChangeRequest}", activeChangeRequest);
    return Results.Ok(new { activeChangeRequest });
});

app.MapPost("/api/simulate/clear-cr", (ILoggerFactory loggerFactory) =>
{
    activeChangeRequest = "";
    loggerFactory.CreateLogger("OrdersApi.Simulation")
        .LogWarning("Cleared active change request");
    return Results.Ok(new { activeChangeRequest });
});

app.MapPost("/api/simulate/health/{mode}", (string mode, ILoggerFactory loggerFactory) =>
{
    if (mode != "healthy" && mode != "unhealthy")
    {
        loggerFactory.CreateLogger("OrdersApi.Simulation")
            .LogWarning("Rejected invalid simulated health mode {HealthMode}", mode);
        return Results.BadRequest(new { error = "mode must be healthy or unhealthy" });
    }

    healthUnhealthy = mode == "unhealthy";
    loggerFactory.CreateLogger("OrdersApi.Simulation")
        .LogWarning("Updated simulated health mode to {HealthMode}", mode);
    return Results.Ok(new { healthUnhealthy });
});

app.MapGet("/api/orders/{id}", (string id, ILoggerFactory loggerFactory) =>
{
    var logger = loggerFactory.CreateLogger("OrdersApi.Orders");
    if (orders.TryGetValue(id, out var result))
    {
        logger.LogInformation("Retrieved order {OrderId}", id);
        return Results.Ok(result);
    }

    logger.LogWarning("Order {OrderId} not found", id);
    return Results.NotFound(new { error = $"Order {id} not found" });
});

app.Run();

record OrderRequest(string CustomerId, string Sku, int Quantity);
record OrderResult(string Id, string CustomerId, string Sku, int Quantity, string Status, string ChangeRequest, DateTimeOffset CreatedAt);
