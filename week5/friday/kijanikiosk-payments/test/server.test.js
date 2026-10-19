'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('../src/server');

async function withServer(fn) {
  const server = createServer().listen(0);
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    await fn(`http://127.0.0.1:${server.address().port}`);
  } finally {
    server.close();
  }
}

test('GET /health', () => withServer(async (base) => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { status: 'ok' });
}));

test('POST /payments creates, then replays on retry', () => withServer(async (base) => {
  const post = () => fetch(`${base}/payments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Idempotency-Key': 'abc-12345' },
    body: JSON.stringify({ phone: '+254712345678', amount: 500, reference: 'ORDER-7' }),
  });
  const first = await post();
  assert.equal(first.status, 201);
  const second = await post();
  assert.equal(second.status, 200);
  assert.equal((await second.json()).id, (await first.json()).id);
}));

test('POST /payments rejects invalid input with 422', () => withServer(async (base) => {
  const res = await fetch(`${base}/payments`, { method: 'POST', body: JSON.stringify({ amount: 5 }) });
  assert.equal(res.status, 422);
}));
