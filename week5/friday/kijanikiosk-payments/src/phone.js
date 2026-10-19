'use strict';

// Kenyan mobile numbers in the formats customers actually type, normalised to 2547XXXXXXXX / 2541XXXXXXXX.
const PATTERN = /^(?:\+?254|0)?([71]\d{8})$/;

function normalisePhone(input) {
  if (typeof input !== 'string') return null;
  const match = input.replace(/[\s-]/g, '').match(PATTERN);
  return match ? `254${match[1]}` : null;
}

module.exports = { normalisePhone };
