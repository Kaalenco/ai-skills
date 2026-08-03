# Pattern: App Code Verification (ASP.NET Core / Container)

Checks to run against the **application code and Dockerfile** whenever a new pipeline is created for a web app or API, or when the user explicitly asks for a webapp/API deployment review. These are not pipeline YAML issues — they are code and image configuration issues that cause silent deployment failures (often reported as **Activation failed** in ACA or a crash-looping pod in Kubernetes).

For each check: read the relevant files (Dockerfile, Program.cs / Startup.cs, launchSettings.json, appsettings.json) and report findings under the same severity groupings used in the review checklist (Critical / Warning / Suggestion).

---

## 1. HTTPS port gating

**What to check:** does the app unconditionally bind an HTTPS port or register HTTPS redirection?

In containerised environments (ACA, Kubernetes) TLS is terminated at the ingress. The container receives plain HTTP. If `UseHttps()` is called without a certificate at startup, .NET 8+ throws:

```
Unable to configure HTTPS endpoint. No server certificate was specified,
and the default developer certificate could not be found or is out of date.
```

ACA reports this as **Activation failed**; Kubernetes as `CrashLoopBackOff`.

**Required pattern** — all three points must be gated on the same variable:

```csharp
// Normalise empty string to null so int.Parse never throws on ""
var httpsPortStr = Environment.GetEnvironmentVariable("ASPNETCORE_HTTPS_PORT");
httpsPortStr = string.IsNullOrWhiteSpace(httpsPortStr) ? null : httpsPortStr;

builder.WebHost.ConfigureKestrel(options =>
{
    options.ListenAnyIP(httpPort);
    if (httpsPortStr is not null)
        options.ListenAnyIP(int.Parse(httpsPortStr), o => o.UseHttps());
});

if (httpsPortStr is not null)
    builder.Services.AddHttpsRedirection(options => options.HttpsPort = int.Parse(httpsPortStr));

// ... later in pipeline:
if (httpsPortStr is not null)
    app.UseHttpsRedirection();
```

**launchSettings.json** must set the variable so local dev keeps HTTPS:

```json
"environmentVariables": {
  "ASPNETCORE_ENVIRONMENT": "Development",
  "ASPNETCORE_HTTP_PORT": "5073",
  "ASPNETCORE_HTTPS_PORT": "7073"
},
"applicationUrl": "https://localhost:7073;http://localhost:5073"
```

**Dockerfile** must NOT set `ASPNETCORE_HTTPS_PORT`. Set only the HTTP port:

```dockerfile
ENV ASPNETCORE_HTTP_PORT=5073
# ASPNETCORE_HTTPS_PORT is intentionally absent — TLS is terminated at the ingress.
```

---

## 2. Health endpoints

**What to check:** does the app expose `/health` and `/ready`?

ACA and Kubernetes use separate probes:

| Endpoint | Probe type | Should query DB? |
|---|---|---|
| `/health` | Liveness / startup | No — process-alive only |
| `/ready` | Readiness | Yes — returns 503 until DB is reachable |

Returning 200 from `/health` without hitting the database lets the pod pass the liveness probe during cold start before the database connection is established.

**Required pattern:**

```csharp
builder.Services
    .AddHealthChecks()
    .AddDbContextCheck<MyDbContext>("database", tags: ["ready"]);

// /health — always 200 if the process is alive (no registered checks run)
app.MapHealthChecks("/health", new HealthCheckOptions
{
    Predicate = _ => false
});

// /ready — 200 only when database is reachable
app.MapHealthChecks("/ready", new HealthCheckOptions
{
    Predicate = check => check.Tags.Contains("ready")
});
```

---

## 3. Port consistency

**What to check:** do the Dockerfile, app code, launchSettings.json, and ACA ingress target port all agree on which port the container listens on?

Check all four locations:

| Location | What to look for |
|---|---|
| `Dockerfile` | `EXPOSE` and `ENV ASPNETCORE_HTTP_PORT` |
| `Program.cs` | `ASPNETCORE_HTTP_PORT` read and passed to `ListenAnyIP` |
| `launchSettings.json` | `ASPNETCORE_HTTP_PORT` and `applicationUrl` |
| ACA ingress / Bicep / pipeline | `--target-port` or ingress config |

Mismatch between any of these causes ACA's health probe to fail → **Activation failed**.

**Note on `CreateEmptyBuilder`:** if the app uses `WebApplication.CreateEmptyBuilder`, `ASPNETCORE_URLS` is **not** applied automatically. Kestrel must be configured explicitly via `ConfigureKestrel`. Setting `ASPNETCORE_URLS` in the Dockerfile has no effect and is misleading — use `ASPNETCORE_HTTP_PORT` instead.

---

## 4. Blocking startup calls

**What to check:** does the app call an external service (database, cache, external API) synchronously during `WebApplication.Build()` or immediately after, before the HTTP host is ready?

Startup-time database calls — e.g. `DatabaseInitializer.Initialize(app.Services)` — block the process until the database responds. If the database is unreachable at the moment the container starts, the process exits before ACA's liveness probe ever succeeds.

**Acceptable patterns:**
- Defer to a hosted `IHostedService` / `BackgroundService` with retry logic.
- Use EF Core's migration API inside a scoped service that retries on transient errors.
- Wrap the call in a try/catch that logs and continues — let the `/ready` probe signal unreadiness rather than crashing.

**Unacceptable:**
- Any call that throws an unhandled exception during startup if the database is temporarily unavailable.

---

## 5. Secrets in appsettings.json

**What to check:** does `appsettings.json` contain real credentials (connection strings, API keys, tokens) that would be committed to source?

All runtime secrets must come from environment variables or Key Vault. `appsettings.json` may contain:
- Provider selection (`Database:Provider`)
- Non-sensitive defaults (log levels, feature flags)
- Localhost-only development connection strings clearly marked as such

Flag any of the following as Critical if found in a file that is committed to the repository:
- Connection strings containing passwords
- JWT signing secrets or encryption keys
- Third-party API keys or tokens

---

## 6. Forwarded headers (reverse proxy / ingress TLS termination)

**What to check:** does the app call `UseForwardedHeaders` before any middleware that uses `HttpContext.Request.Scheme` or `HttpContext.Connection.RemoteIpAddress`?

In ACA, Kubernetes, and any setup where TLS is terminated at the ingress, the container receives plain HTTP. Without forwarded-headers middleware, `HttpContext.Request.Scheme` is always `http`, which causes:

- **OpenAPI / Scalar server URL shows `http://`** — Scalar is served over HTTPS (via the ingress); the browser blocks any fetch to an `http://` URL as mixed content, producing a **"failed to fetch"** error in the Scalar UI.
- **`UseHttpsRedirection` loops or misdirects** — the app cannot know the client is already on HTTPS.
- **IP-based rate limiting or logging records the proxy IP** instead of the real client IP.

**Required pattern:**

```csharp
// Must be registered before MapOpenApi, UseHttpsRedirection, and any middleware
// that inspects Request.Scheme or RemoteIpAddress.
var forwardedOptions = new ForwardedHeadersOptions
{
    ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto,
};
// Clear defaults — ACA/Kubernetes internal proxy IPs are not fixed.
// The ingress is the network boundary; trusting any forwarder is safe.
forwardedOptions.KnownNetworks.Clear();
forwardedOptions.KnownProxies.Clear();
app.UseForwardedHeaders(forwardedOptions);
```

Add `using Microsoft.AspNetCore.HttpOverrides;` — the types are in the `Microsoft.AspNetCore.HttpOverrides` namespace, which ships in the ASP.NET Core shared framework (no extra NuGet package required).

**Flag as Critical** if `UseForwardedHeaders` is absent and the app is deployed behind an ingress that terminates TLS (ACA, AKS, nginx, etc.).

---

## 7. Non-root container user

**What to check:** does the Dockerfile run as a non-root user?

The `mcr.microsoft.com/dotnet/aspnet` base image (8.0+) defines an `app` user (UID 1654) and sets it as the default. Explicitly declaring `USER $APP_UID` (or `USER app`) makes the intent visible without relying on base image knowledge:

```dockerfile
USER $APP_UID
```

Flag as Warning if the container runs as root (no `USER` instruction and base image default is root).
