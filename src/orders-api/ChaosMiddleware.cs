/// <summary>
/// Thrown by ChaosMiddleware to simulate unhandled exceptions.
/// ASP.NET's exception handler will log it and return a 500.
/// </summary>
public class ChaosMonkeyException(string message) : Exception(message) { }

/// <summary>
/// Middleware that randomly injects faults when CHAOS_ENABLED=true.
///
/// Fault profile (per request):
///   /health path  → 40% chance of 503
///   API paths     → 15% unhandled exception (ChaosMonkeyException → 500)
///                 → 30% direct 500 response
///                 → 25% latency spike (3–10 s)
///   Every 10th request → 50 MB memory pressure allocation
/// </summary>
public class ChaosMiddleware(RequestDelegate next, ILogger<ChaosMiddleware> logger)
{
    private static int _requestCount;
    // Hold references so GC doesn't collect them — simulates a memory leak.
    private static readonly List<byte[]> _memoryPressure = [];

    public async Task InvokeAsync(HttpContext context)
    {
        var roll  = Random.Shared.Next(1, 101);
        var path  = context.Request.Path.Value ?? string.Empty;
        var count = Interlocked.Increment(ref _requestCount);

        // ── health probe failures (40%) ──────────────────────────────────────
        if (path.StartsWith("/health", StringComparison.OrdinalIgnoreCase))
        {
            if (roll <= 40)
            {
                logger.LogError("CHAOS: health probe failure injected (503) on request #{Count}", count);
                context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
                await context.Response.WriteAsJsonAsync(new { status = "chaos-unhealthy", chaos = true });
                return;
            }
        }
        else
        {
            // ── unhandled exception → 500 (15%) ─────────────────────────────
            if (roll <= 15)
            {
                logger.LogError("CHAOS: throwing ChaosMonkeyException on request #{Count} [{Path}]", count, path);
                throw new ChaosMonkeyException($"Chaos monkey struck request #{count} on {path}");
            }

            // ── direct 500 response (30%) ────────────────────────────────────
            if (roll <= 45)
            {
                logger.LogError("CHAOS: injecting HTTP 500 on request #{Count} [{Path}]", count, path);
                context.Response.StatusCode = StatusCodes.Status500InternalServerError;
                await context.Response.WriteAsJsonAsync(new { error = "chaos-500", chaos = true, path });
                return;
            }

            // ── latency spike 3–10 s (25%) ───────────────────────────────────
            if (roll <= 70)
            {
                var delayMs = Random.Shared.Next(3_000, 10_001);
                logger.LogWarning("CHAOS: injecting {Delay}ms latency on request #{Count} [{Path}]", delayMs, count, path);
                await Task.Delay(delayMs, context.RequestAborted);
            }
        }

        // ── memory pressure spike every 10th request (50 MB) ────────────────
        if (count % 10 == 0)
        {
            logger.LogWarning("CHAOS: allocating 50 MB memory pressure (request #{Count})", count);
            lock (_memoryPressure)
                _memoryPressure.Add(new byte[50 * 1024 * 1024]);
        }

        await next(context);
    }
}
