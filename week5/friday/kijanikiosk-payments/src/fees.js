'use strict';

// Transaction fee bands in KES. Amounts are whole shillings; upper bounds are inclusive.
const FEE_BANDS = [
  { upTo: 100, fee: 0 },
  { upTo: 500, fee: 7 },
  { upTo: 1000, fee: 13 },
  { upTo: 1500, fee: 23 },
  { upTo: 2500, fee: 33 },
  { upTo: 3500, fee: 53 },
  { upTo: 5000, fee: 57 },
  { upTo: 7500, fee: 78 },
  { upTo: 10000, fee: 90 },
  { upTo: 15000, fee: 100 },
  { upTo: 20000, fee: 105 },
  { upTo: 250000, fee: 108 },
];
const MIN_AMOUNT = 1;
const MAX_AMOUNT = 250000;

function calculateFee(amount) {
  if (!Number.isInteger(amount) || amount < MIN_AMOUNT || amount > MAX_AMOUNT) {
    throw new RangeError(`amount must be a whole number of shillings between ${MIN_AMOUNT} and ${MAX_AMOUNT}`);
  }
  return FEE_BANDS.find((band) => amount <= band.upTo).fee;
}

module.exports = { calculateFee, MIN_AMOUNT, MAX_AMOUNT };
