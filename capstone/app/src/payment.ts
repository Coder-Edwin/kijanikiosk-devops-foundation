import { randomUUID } from "node:crypto";

export interface PaymentRequest {
  customerId: string;
  amount: number;
  currency: string;
  method?: string;
}

export interface Receipt extends PaymentRequest {
  receiptId: string;
  environment: string;
  version: string;
  createdAt: string;
}

const CURRENCIES = new Set(["KES", "UGX", "TZS", "USD"]);

// Pure validation, unit-tested without a server or S3.
export function validatePayment(body: unknown): { ok: true; value: PaymentRequest } | { ok: false; errors: string[] } {
  const errors: string[] = [];
  const b = (body ?? {}) as Record<string, unknown>;
  if (typeof b.customerId !== "string" || !/^[A-Za-z0-9_-]{3,64}$/.test(b.customerId)) errors.push("customerId must be 3-64 letters, digits, - or _");
  if (typeof b.amount !== "number" || !Number.isFinite(b.amount) || b.amount <= 0 || b.amount > 1_000_000) errors.push("amount must be a number between 0 and 1,000,000");
  if (typeof b.currency !== "string" || !CURRENCIES.has(b.currency)) errors.push(`currency must be one of ${[...CURRENCIES].join(", ")}`);
  if (b.method !== undefined && (typeof b.method !== "string" || b.method.length > 32)) errors.push("method must be a short string");
  if (errors.length) return { ok: false, errors };
  return { ok: true, value: { customerId: b.customerId as string, amount: Math.round((b.amount as number) * 100) / 100, currency: b.currency as string, method: (b.method as string) ?? "mpesa" } };
}

export function buildReceipt(p: PaymentRequest, environment: string, version: string, now = new Date()): Receipt {
  return { receiptId: randomUUID(), ...p, environment, version, createdAt: now.toISOString() };
}

// receipts/2026/11/13/<id>.json: date-partitioned so listing a day is cheap.
export function receiptKey(r: Receipt): string {
  const d = r.createdAt.slice(0, 10).split("-");
  return `receipts/${d[0]}/${d[1]}/${d[2]}/${r.receiptId}.json`;
}
