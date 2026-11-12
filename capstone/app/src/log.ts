// Structured JSON logging: one object per line, so logs can be searched by
// field (level, route, receiptId) instead of grepping free text.
type Level = "debug" | "info" | "warn" | "error";
const order: Record<Level, number> = { debug: 10, info: 20, warn: 30, error: 40 };
const threshold = order[(process.env.LOG_LEVEL as Level) ?? "info"] ?? order.info;

const base = {
  service: "kk-payments",
  env: process.env.APP_ENV ?? "unknown",
  version: process.env.APP_VERSION ?? "unknown",
};

export function log(level: Level, msg: string, fields: Record<string, unknown> = {}): void {
  if (order[level] < threshold) return;
  const line = JSON.stringify({ ts: new Date().toISOString(), level, msg, ...base, ...fields });
  (level === "error" || level === "warn" ? process.stderr : process.stdout).write(line + "\n");
}
