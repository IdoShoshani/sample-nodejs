const test = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('../app');

test('GET /ready returns 200 "Ready"', async () => {
  const res = await request(app).get('/ready');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.text, 'Ready');
});

test('GET /live returns 200 "Alive"', async () => {
  const res = await request(app).get('/live');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.text, 'Alive');
});

test('GET /my-app returns "Hello, World!"', async () => {
  const res = await request(app).get('/my-app');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.text, 'Hello, World!');
});

test('GET /metrics exposes Prometheus metrics', async () => {
  const res = await request(app).get('/metrics');
  assert.strictEqual(res.status, 200);
  assert.match(res.text, /root_access_total|process_cpu/);
});
