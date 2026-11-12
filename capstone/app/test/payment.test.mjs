// Unit tests for the pure payment logic; run inside the image build so a
// failing test stops the pipeline before anything is pushed.
import { test } from "node:test";
import assert from "node:assert/strict";
import { validatePayment, buildReceipt, receiptKey } from "../dist/payment.js";

test("accepts a valid M-Pesa payment and rounds to cents", () => {
  const r = validatePayment({ customerId: "cust-001", amount: 1499.999, currency: "KES" });
  assert.equal(r.ok, true);
  assert.equal(r.value.amount, 1500);
  assert.equal(r.value.method, "mpesa");
});

test("rejects zero, negative and non-numeric amounts", () => {
  for (const amount of [0, -5, "100", Number.NaN]) {
    const r = validatePayment({ customerId: "cust-001", amount, currency: "KES" });
    assert.equal(r.ok, false, `amount ${String(amount)} should be rejected`);
  }
});

test("rejects unsupported currency and malformed customer id", () => {
  const r = validatePayment({ customerId: "x", amount: 10, currency: "EUR" });
  assert.equal(r.ok, false);
  assert.equal(r.errors.length, 2);
});

test("receipt key is date-partitioned and ends with the receipt id", () => {
  const rc = buildReceipt({ customerId: "cust-001", amount: 10, currency: "KES", method: "mpesa" }, "staging", "1.0.0-abc1234", new Date("2026-11-13T08:00:00Z"));
  assert.match(receiptKey(rc), new RegExp(`^receipts/2026/11/13/${rc.receiptId}\\.json$`));
  assert.equal(rc.environment, "staging");
});
