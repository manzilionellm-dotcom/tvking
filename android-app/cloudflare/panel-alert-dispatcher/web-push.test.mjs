import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, randomBytes, createPublicKey, verify, webcrypto } from 'node:crypto';
import { validPushSubscription, validAlertPayload, readVapidConfig, sendWebPush } from './web-push.js';

const pair = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
const jwk = pair.privateKey.export({ format: 'jwk' });
const b64 = (value) => Buffer.from(value).toString('base64url');
const publicKey = Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]);
const env = { PANEL_PUSH_PUBLIC_KEY: b64(publicKey), PANEL_PUSH_PRIVATE_KEY: jwk.d,
  PANEL_PUSH_SUBJECT: 'https://atlas-console-k7q2.vercel.app/' };
const receiver = await webcrypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits']);
const receiverBytes = new Uint8Array(await webcrypto.subtle.exportKey('raw', receiver.publicKey));
const auth = randomBytes(16);
const subscription = { endpoint: 'https://fcm.googleapis.com/fcm/send/fixture-only-never-sent',
  expirationTime: null, keys: { p256dh: b64(receiverBytes), auth: b64(auth) } };
const payload = { v: 1, event_id: 'activation:fixture-1', type: 'activation', title: 'Licence activée',
  message: 'Une licence vient d’être activée.', url: '/devices?mac=MK%3A11%3A22%3A33%3A44%3A55' };

test('services HTTPS autorisés, destinations locales et aucune propriété secrète', () => {
  assert.equal(validPushSubscription(subscription), true);
  for (const endpoint of ['http://fcm.googleapis.com/x', 'https://127.0.0.1/x',
    'https://fcm.googleapis.com.evil.test/x', 'https://user:secret@fcm.googleapis.com/x',
    'https://fcm.googleapis.com:8443/x', 'https://fcm.googleapis.com/x#secret', 'https://metadata.google.internal/x']) {
    assert.equal(validPushSubscription({ ...subscription, endpoint }), false);
  }
  assert.equal(validPushSubscription({ ...subscription, keys: { ...subscription.keys, auth: 'invalid' } }), false);
  assert.equal(validPushSubscription({ ...subscription, expirationTime: Date.now() - 1000 }), false);
  assert.equal(validAlertPayload(payload), true);
  for (const url of ['//evil.test/devices?mac=MK:11:22:33:44:55',
    'https://evil.test/', '/devices?mac=MK:11:22:33:44:55&token=secret', '/account?mac=MK:11:22:33:44:55',
    '/devices?mac=MK:11:22:33:44:55#secret', '/devices?mac=MK:11:22:33:44:55&mac=AA:BB:CC:DD:EE:FF']) {
    assert.equal(validAlertPayload({ ...payload, url }), false);
  }
  assert.equal(validAlertPayload({ ...payload, device_key: 'secret' }), false);
  assert.equal(validAlertPayload({ ...payload, title: 'title\nhidden' }), false);
  assert.throws(() => readVapidConfig({ ...env, PANEL_PUSH_PRIVATE_KEY: '' }), /configuration/);
});

// Ce déchiffrement indépendant utilise les primitives WebCrypto de Node, pas
// les fonctions internes de la dépendance qui produit le message.
async function decrypt(body) {
  const bytes = new Uint8Array(body);
  const salt = bytes.slice(0, 16);
  assert.equal(new DataView(bytes.buffer, bytes.byteOffset).getUint32(16), 4096);
  assert.equal(bytes[20], 65);
  const ephemeral = bytes.slice(21, 86);
  const senderPublic = await webcrypto.subtle.importKey('raw', ephemeral, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const shared = await webcrypto.subtle.deriveBits({ name: 'ECDH', public: senderPublic }, receiver.privateKey, 256);
  async function hkdf(ikm, saltBytes, info, bits) {
    const key = await webcrypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
    return webcrypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: saltBytes, info }, key, bits);
  }
  const keyInfo = Buffer.concat([Buffer.from('WebPush: info\0'), receiverBytes, ephemeral]);
  const ikm = await hkdf(shared, auth, keyInfo, 256);
  const cek = await hkdf(ikm, salt, Buffer.from('Content-Encoding: aes128gcm\0'), 128);
  const nonce = await hkdf(ikm, salt, Buffer.from('Content-Encoding: nonce\0'), 96);
  const key = await webcrypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']);
  const clear = new Uint8Array(await webcrypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, bytes.slice(86)));
  let end = clear.length - 1;
  while (clear[end] === 0) end--;
  assert.equal(clear[end], 2);
  return JSON.parse(new TextDecoder().decode(clear.slice(0, end)));
}

test('chiffrement réel déchiffrable et signature VAPID vérifiée, sans réseau', async () => {
  let seen = 0;
  const result = await sendWebPush(subscription, payload, env, async (url, request) => {
    seen++;
    assert.equal(url, subscription.endpoint);
    assert.equal(request.redirect, 'manual');
    assert.equal(request.headers['content-encoding'], 'aes128gcm');
    assert.equal(request.headers.ttl, '3600');
    assert.equal(request.body.byteLength, 4096);
    assert.deepEqual(await decrypt(request.body), payload);
    const match = /^vapid t=([^,]+), k=(.+)$/.exec(request.headers.authorization);
    assert.ok(match);
    assert.equal(match[2], env.PANEL_PUSH_PUBLIC_KEY);
    const [head, claims, signature] = match[1].split('.');
    const decoded = JSON.parse(Buffer.from(claims, 'base64url'));
    assert.equal(decoded.aud, 'https://fcm.googleapis.com');
    assert.equal(decoded.sub, env.PANEL_PUSH_SUBJECT);
    assert.ok(decoded.exp > Date.now() / 1000 && decoded.exp < Date.now() / 1000 + 86400);
    assert.equal(verify('sha256', Buffer.from(head + '.' + claims),
      { key: createPublicKey(pair.privateKey), dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')), true);
    assert.equal(JSON.stringify(request.body).includes(payload.message), false);
    return new Response(null, { status: 201 });
  });
  assert.equal(seen, 1);
  assert.deepEqual(result, { state: 'sent', status: 201, error: null });
});

test('résultats de transport classés sans prétendre lecture ni suivre une redirection', async () => {
  for (const [status, state] of [[410, 'gone'], [404, 'gone'], [429, 'retry'], [503, 'retry'],
    [400, 'failed'], [401, 'failed'], [302, 'failed']]) {
    const result = await sendWebPush(subscription, payload, env,
      async () => new Response('private provider details', { status, headers: { 'Retry-After': '120' } }));
    assert.equal(result.state, state);
    assert.equal(result.status, status);
    assert.equal(JSON.stringify(result).includes('private provider'), false);
    if (state === 'retry') assert.equal(result.retryAfter, 120);
  }
  const network = await sendWebPush(subscription, payload, env, async () => { throw new Error('private endpoint'); });
  assert.equal(network.state, 'retry');
  assert.equal(JSON.stringify(network).includes('private endpoint'), false);
  let calls = 0;
  const invalid = await sendWebPush({ ...subscription, endpoint: 'https://localhost/x' }, payload, env,
    async () => { calls++; return new Response(); });
  assert.equal(invalid.state, 'invalid');
  assert.equal(calls, 0);
});
