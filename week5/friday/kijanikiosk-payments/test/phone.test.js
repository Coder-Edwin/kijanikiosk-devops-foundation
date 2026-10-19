'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { normalisePhone } = require('../src/phone');

test('accepts the formats customers type', () => {
  for (const input of ['0712345678', '+254712345678', '254712345678', '712345678', '0712 345 678', '0712-345-678']) {
    assert.equal(normalisePhone(input), '254712345678', input);
  }
});

test('accepts 01xx numbers', () => {
  assert.equal(normalisePhone('0110123456'), '254110123456');
});

test('rejects numbers that are not Kenyan mobiles', () => {
  for (const input of ['0212345678', '07123456', '+255712345678', 'abc', '', null, 712345678]) {
    assert.equal(normalisePhone(input), null, String(input));
  }
});
