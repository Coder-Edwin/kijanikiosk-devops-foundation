import http from "node:http";
import os from "node:os";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { log } from "./log";
import { defineCounter, inc, render } from "./metrics";
import { validatePayment, buildReceipt, receiptKey } from "./payment";

// ---- Configuration (injected from the per-environment ConfigMap) -------------
const REQUIRED = ["APP_ENV", "DB_HOST", "RECEIPTS_BUCKET", "AWS_REGION"] as const;
const missing = REQUIRED.filter((k) => !process.env[k]);
const cfg = {
  port: Number(process.env.PORT ?? 3001),
  version: process.env.APP_VERSION ?? "unknown",
  env: process.env.APP_ENV ?? "unknown",
  dbHost: process.env.DB_HOST ?? "",
  bucket: process.env.RECEIPTS_BUCKET ?? "",
  region: process.env.AWS_REGION ?? "us-east-1",
  s3Endpoint: process.env.S3_ENDPOINT || undefined,
};

// With an S3_ENDPOINT (LocalStack) the SDK still needs some credentials, and
// LocalStack accepts any value. Against real AWS the endpoint is unset and the
// SDK uses the Pod's IAM role instead; no credentials live in code or config.
const s3 = new S3Client({
  region: cfg.region,
  endpoint: cfg.s3Endpoint,
  forcePathStyle: Boolean(cfg.s3Endpoint),
  ...(cfg.s3Endpoint ? { credentials: { accessKeyId: "localstack", secretAccessKey: "localstack" } } : {}),
});

defineCounter("kk_payments_http_requests_total", "HTTP requests by method, route and status code");
defineCounter("kk_payments_receipt_writes_total", "Receipt writes to S3 by result");

let ready = missing.length === 0;
const startedAt = Date.now();

function send(res: http.ServerResponse, code: number, body: unknown, route: string, method: string): void {
  res.writeHead(code, { "Content-Type": typeof body === "string" ? "text/plain; version=0.0.4" : "application/json" });
  res.end(typeof body === "string" ? body : JSON.stringify(body));
  inc("kk_payments_http_requests_total", { method, route, code: String(code) });
}

function readJson(req: http.IncomingMessage, limit = 16_384): Promise<unknown> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => {
      size += c.length;
      if (size > limit) { reject(new Error("body too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => {
      try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {}); } catch { reject(new Error("invalid JSON")); }
    });
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  const method = req.method ?? "GET";
  const path = (req.url ?? "/").split("?")[0];
  const t0 = Date.now();
  try {
    if (method === "GET" && path === "/health") {
      // Liveness: the process is up and serving.
      return send(res, 200, { status: "ok", service: "kk-payments", version: cfg.version, environment: cfg.env, dbHost: cfg.dbHost, pod: os.hostname(), uptimeSeconds: Math.round((Date.now() - startedAt) / 1000) }, "/health", method);
    }
    if (method === "GET" && path === "/ready") {
      // Readiness: configuration is complete and we are not shutting down.
      return ready ? send(res, 200, { ready: true }, "/ready", method) : send(res, 503, { ready: false, missingConfig: missing }, "/ready", method);
    }
    if (method === "GET" && path === "/metrics") {
      const extra = [
        "# HELP kk_payments_build_info Build and environment of the running instance",
        "# TYPE kk_payments_build_info gauge",
        `kk_payments_build_info{version="${cfg.version}",environment="${cfg.env}"} 1`,
        "# HELP kk_payments_uptime_seconds Seconds since the process started",
        "# TYPE kk_payments_uptime_seconds gauge",
        `kk_payments_uptime_seconds ${Math.round((Date.now() - startedAt) / 1000)}`,
      ];
      return send(res, 200, render(extra), "/metrics", method);
    }
    if (method === "POST" && path === "/payments") {
      let body: unknown;
      try { body = await readJson(req); } catch (e) { return send(res, 400, { error: (e as Error).message }, "/payments", method); }
      const v = validatePayment(body);
      if (!v.ok) {
        log("warn", "payment rejected", { route: "/payments", errors: v.errors });
        return send(res, 400, { error: "validation failed", details: v.errors }, "/payments", method);
      }
      const receipt = buildReceipt(v.value, cfg.env, cfg.version);
      const key = receiptKey(receipt);
      try {
        await s3.send(new PutObjectCommand({ Bucket: cfg.bucket, Key: key, Body: JSON.stringify(receipt), ContentType: "application/json" }), { abortSignal: AbortSignal.timeout(3000) });
        inc("kk_payments_receipt_writes_total", { result: "success" });
      } catch (e) {
        // Fail closed and visibly: the customer gets a clear 503, the error is
        // logged with the receipt id, and the error counter feeds the alert.
        inc("kk_payments_receipt_writes_total", { result: "error" });
        log("error", "receipt write failed", { receiptId: receipt.receiptId, bucket: cfg.bucket, error: (e as Error).name, detail: (e as Error).message });
        return send(res, 503, { error: "receipt storage unavailable, payment not recorded", receiptId: receipt.receiptId }, "/payments", method);
      }
      log("info", "payment accepted", { receiptId: receipt.receiptId, amount: receipt.amount, currency: receipt.currency, bucket: cfg.bucket, key, ms: Date.now() - t0 });
      return send(res, 201, { receiptId: receipt.receiptId, bucket: cfg.bucket, key, environment: cfg.env, version: cfg.version }, "/payments", method);
    }
    return send(res, 404, { error: "not found" }, "other", method);
  } catch (e) {
    log("error", "unhandled error", { path, error: (e as Error).message });
    return send(res, 500, { error: "internal error" }, "other", method);
  }
});

server.listen(cfg.port, () => {
  if (missing.length) log("error", "missing configuration; readiness will fail", { missing });
  log("info", "kk-payments started", { port: cfg.port, dbHost: cfg.dbHost, bucket: cfg.bucket, s3Endpoint: cfg.s3Endpoint ?? "aws-default" });
});

// Graceful shutdown: stop receiving traffic first, then finish in-flight work.
for (const sig of ["SIGTERM", "SIGINT"] as const) {
  process.on(sig, () => {
    ready = false;
    log("info", "shutdown requested", { signal: sig });
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 10_000).unref();
  });
}
