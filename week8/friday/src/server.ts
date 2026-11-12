import http from "node:http";
import os from "node:os";

const PORT = Number(process.env.PORT ?? 3001);
// Baked into the image at build time from the semver-SHA tag, so /health
// always reports exactly which image is running.
const VERSION = process.env.APP_VERSION ?? "unknown";
const startedAt = Date.now();

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(
      JSON.stringify({
        status: "ok",
        service: "kk-payments",
        version: VERSION,
        pod: os.hostname(),
        uptimeSeconds: Math.round((Date.now() - startedAt) / 1000),
      })
    );
    return;
  }
  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "not found" }));
});

server.listen(PORT, () => {
  console.log(`kk-payments ${VERSION} listening on ${PORT}`);
});

// Exit cleanly when Kubernetes stops the Pod.
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
