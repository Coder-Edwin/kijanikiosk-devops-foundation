'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createLedger } = require('../src/payments');

const valid = { phone: '0712345678', amount: 1200, reference: 'ORDER-1001', idempotencyKey: 'key-0001' };

test('creates a pending payment with fee and total', () => {
  const result = createLedger().createPayment(valid);
  assert.equal(result.ok, true);
  assert.equal(result.payment.msisdn, '254712345678');
  assert.equal(result.payment.fee, 23);
  assert.equal(result.payment.total, 1223);
  assert.equal(result.payment.status, 'PENDING');
});

test('a retried request with the same idempotency key is not charged twice', () => {
  const ledger = createLedger();
  const first = ledger.createPayment(valid);
  const retry = ledger.createPayment(valid);
  assert.equal(retry.replayed, true);
  assert.equal(retry.payment.id, first.payment.id);
  assert.equal(ledger.size(), 1);
});

test('returns every validation error at once', () => {
  const result = createLedger().createPayment({ phone: 'x', amount: 0, reference: '', idempotencyKey: '1' });
  assert.equal(result.ok, false);
  assert.equal(result.errors.length, 4);
});
