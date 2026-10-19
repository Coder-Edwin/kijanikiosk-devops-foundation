'use strict';

const http = require('node:http');
const { createLedger } = require('./payments');

function createServer(ledger = createLedger()) {
  return http.createServer((req, res) => {
    const send = (status, body) => {
      res.writeHead(status, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(body));
    };

    if (req.method === 'GET' && req.url === '/health') return send(200, { status: 'ok' });

    if (req.method === 'POST' && req.url === '/payments') {
      let raw = '';
      req.on('data', (chunk) => {
        raw += chunk;
        if (raw.length > 10000) req.destroy();
      });
      req.on('end', () => {
        let body;
        try {
          body = JSON.parse(raw);
        } catch {
          return send(400, { errors: ['body must be JSON'] });
        }
        const result = ledger.createPayment({ ...body, idempotencyKey: req.headers['idempotency-key'] });
        if (!result.ok) return send(422, { errors: result.errors });
        return send(result.replayed ? 200 : 201, result.payment);
      });
      return undefined;
    }

    return send(404, { errors: ['not found'] });
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  createServer().listen(port, () => console.log(`kijanikiosk-payments listening on ${port}`));
}

module.exports = { createServer };
