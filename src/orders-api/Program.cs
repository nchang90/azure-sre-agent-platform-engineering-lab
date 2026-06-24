using Microsoft.AspNetCore.HttpOverrides;
using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();
builder.Services.Configure<ForwardedHeadersOptions>(options =>
{
    options.ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto;
});

var app = builder.Build();

app.UseForwardedHeaders();

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

app.MapGet("/", () => Results.Ok(new
{
    service = "orders-api",
    version = "1.0.0",
    activeChangeRequest,
    message = "Orders API is running"
}));

app.MapGet("/health", () => healthUnhealthy
    ? Results.Problem(title: "unhealthy", statusCode: 503)
    : Results.Ok(new { status = "healthy", service = "orders-api", activeChangeRequest }));

app.MapPost("/api/orders", (OrderRequest request, IConfiguration config) =>
{
    if (request.Quantity <= 0)
    {
        return Results.BadRequest(new { error = "Quantity must be greater than zero" });
    }

    var configuredFailureRate = config.GetValue<int?>("Simulation:FailureRatePercent") ?? 0;
    var failureRate = runtimeFailureRatePercent > 0 ? runtimeFailureRatePercent : configuredFailureRate;
    var roll = Random.Shared.Next(1, 101);

    
    if (failureRate > 0 && roll <= failureRate)
    {
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
    return Results.Ok(result);
});

// Demo endpoint that always 500s — useful for quick alert-firing.
app.MapGet("/api/orders/fail", () =>
    Results.Problem(
        title: "Order processing failed",
        detail: $"Forced failure (CR={activeChangeRequest})",
        statusCode: StatusCodes.Status500InternalServerError));

app.MapPost("/api/simulate/failure-rate/{percent:int}", (int percent) =>
{
    if (percent < 0 || percent > 100)
    {
        return Results.BadRequest(new { error = "Failure rate must be between 0 and 100" });
    }

    runtimeFailureRatePercent = percent;
    return Results.Ok(new
    {
        status = "updated",
        failureRatePercent = runtimeFailureRatePercent
    });
});

app.MapPost("/api/simulate/reset", () =>
{
    runtimeFailureRatePercent = 0;
    return Results.Ok(new
    {
        status = "reset",
        failureRatePercent = runtimeFailureRatePercent
    });
});

// Set the active CR at runtime (simulates deploy pipeline announcing a change window).
app.MapPost("/api/simulate/active-cr/{cr}", (string cr) =>
{
    activeChangeRequest = cr;
    return Results.Ok(new { activeChangeRequest });
});

app.MapPost("/api/simulate/clear-cr", () =>
{
    activeChangeRequest = "";
    return Results.Ok(new { activeChangeRequest });
});

app.MapPost("/api/simulate/health/{mode}", (string mode) =>
{
    if (mode != "healthy" && mode != "unhealthy")
        return Results.BadRequest(new { error = "mode must be healthy or unhealthy" });
    healthUnhealthy = mode == "unhealthy";
    return Results.Ok(new { healthUnhealthy });
});

app.MapGet("/api/orders/{id}", (string id) =>
{
    return orders.TryGetValue(id, out var result)
        ? Results.Ok(result)
        : Results.NotFound(new { error = $"Order {id} not found" });
});

app.Run();

record OrderRequest(string CustomerId, string Sku, int Quantity);
record OrderResult(string Id, string CustomerId, string Sku, int Quantity, string Status, string ChangeRequest, DateTimeOffset CreatedAt);
