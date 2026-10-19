'use strict';

const crypto = require('node:crypto');
const { normalisePhone } = require('./phone');
const { calculateFee } = require('./fees');

// In-memory ledger keyed by idempotency key: a retried request never charges a customer twice.
function createLedger() {
  const byKey = new Map();

  function createPayment({ phone, amount, reference, idempotencyKey }) {
    const errors = [];
    const msisdn = normalisePhone(phone);
    if (!msisdn) errors.push('phone must be a valid Kenyan mobile number');
    if (typeof reference !== 'string' || reference.trim() === '' || reference.length > 32) {
      errors.push('reference is required (max 32 characters)');
    }
    if (typeof idempotencyKey !== 'string' || idempotencyKey.length < 8) {
      errors.push('idempotencyKey is required (min 8 characters)');
    }
    let fee = null;
    try {
      fee = calculateFee(amount);
    } catch (err) {
      errors.push(err.message);
    }
    if (errors.length > 0) return { ok: false, errors };

    if (byKey.has(idempotencyKey)) return { ok: true, payment: byKey.get(idempotencyKey), replayed: true };

    const payment = Object.freeze({
      id: crypto.randomUUID(),
      msisdn,
      amount,
      fee,
      total: amount + fee,
      reference: reference.trim(),
      status: 'PENDING',
      createdAt: new Date().toISOString(),
    });
    byKey.set(idempotencyKey, payment);
    return { ok: true, payment, replayed: false };
  }

  return { createPayment, size: () => byKey.size };
}

module.exports = { createLedger };
