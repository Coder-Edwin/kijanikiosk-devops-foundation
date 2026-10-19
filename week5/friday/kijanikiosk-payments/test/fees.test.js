'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { calculateFee } = require('../src/fees');

test('band edges are inclusive', () => {
  assert.equal(calculateFee(100), 0);
  assert.equal(calculateFee(101), 7);
  assert.equal(calculateFee(500), 7);
  assert.equal(calculateFee(1000), 13);
  assert.equal(calculateFee(250000), 108);
});

test('rejects amounts outside the allowed range', () => {
  for (const amount of [0, -5, 250001, 10.5, '100', NaN]) {
    assert.throws(() => calculateFee(amount), RangeError, String(amount));
  }
});
