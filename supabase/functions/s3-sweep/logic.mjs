/*
 * s3-sweep/logic.mjs — everything the sweep decides, with no network.
 *
 * Plain JavaScript so the same file runs in the Deno edge function and in
 * the Node suite (tests/s3sweep.js), which checks the signer against AWS's
 * published Signature Version 4 examples and the decisions against every
 * case the brief names. Nothing here fetches, reads a secret or deletes.
 */

const enc = new TextEncoder();
const toBytes = (x) => (typeof x === 'string' ? enc.encode(x) : x || new Uint8Array(0));
const hex = (buf) => Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');

/* ---- MD5, for DeleteObjects' required Content-MD5 -------------------------
   Web Crypto has no MD5, and the header is mandatory on a multi-object
   delete, so it is written out here (RFC 1321) and checked in the suite
   against Node's own. */
const S = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
const K = Array.from({ length: 64 }, (_, i) => Math.floor(Math.abs(Math.sin(i + 1)) * 2 ** 32) >>> 0);

export function md5(input) {
  const msg = toBytes(input);
  const len = msg.length;
  const padded = new Uint8Array(((len + 8) >> 6) * 64 + 64);
  padded.set(msg);
  padded[len] = 0x80;
  const dv = new DataView(padded.buffer);
  dv.setUint32(padded.length - 8, (len * 8) >>> 0, true);
  dv.setUint32(padded.length - 4, Math.floor(len / 0x20000000), true);
  let a0 = 0x67452301, b0 = 0xefcdab89, c0 = 0x98badcfe, d0 = 0x10325476;
  for (let off = 0; off < padded.length; off += 64) {
    let A = a0, B = b0, C = c0, D = d0;
    for (let i = 0; i < 64; i++) {
      let F, g;
      if (i < 16) { F = (B & C) | (~B & D); g = i; }
      else if (i < 32) { F = (D & B) | (~D & C); g = (5 * i + 1) % 16; }
      else if (i < 48) { F = B ^ C ^ D; g = (3 * i + 5) % 16; }
      else { F = C ^ (B | ~D); g = (7 * i) % 16; }
      F = (F + A + K[i] + dv.getUint32(off + g * 4, true)) >>> 0;
      A = D; D = C; C = B;
      B = (B + ((F << S[i]) | (F >>> (32 - S[i])))) >>> 0;
    }
    a0 = (a0 + A) >>> 0; b0 = (b0 + B) >>> 0; c0 = (c0 + C) >>> 0; d0 = (d0 + D) >>> 0;
  }
  const out = new Uint8Array(16);
  const ov = new DataView(out.buffer);
  [a0, b0, c0, d0].forEach((w, i) => ov.setUint32(i * 4, w, true));
  return out;
}

export function base64(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s);
}

/* ---- Signature Version 4 ------------------------------------------------ */
async function sha256(data) { return new Uint8Array(await crypto.subtle.digest('SHA-256', toBytes(data))); }
async function hmac(key, data) {
  const k = await crypto.subtle.importKey('raw', toBytes(key), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', k, toBytes(data)));
}
export async function sha256hex(data) { return hex(await sha256(data)); }

/* RFC 3986: everything but A-Z a-z 0-9 - _ . ~ is percent encoded. */
export const uriEncode = (s) => encodeURIComponent(s).replace(/[!'()*]/g, (c) => '%' + c.charCodeAt(0).toString(16).toUpperCase());

/* The path is encoded once, segment by segment, as S3 expects (the generic
   test vectors use paths that encode the same either way). */
const canonicalPath = (p) => (p || '/').split('/').map(uriEncode).join('/');

export function canonicalQuery(query) {
  const pairs = Array.isArray(query) ? query : Object.entries(query || {});
  return pairs
    .map(([k, v]) => [uriEncode(k), uriEncode(v == null ? '' : String(v))])
    .sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : x[1] < y[1] ? -1 : x[1] > y[1] ? 1 : 0))
    .map(([k, v]) => k + '=' + v).join('&');
}

/**
 * Sign one request. `headers` are the headers to send and sign (host is
 * added); `payloadHash` defaults to the SHA-256 of `body`. With `s3: true`
 * the payload hash also rides as x-amz-content-sha256, which S3 requires.
 * Answers the headers to send, plus the intermediate strings for the suite.
 */
export async function sign({ method, host, path = '/', query = {}, headers = {}, body = '',
  accessKeyId, secretAccessKey, region, service, amzDate, s3 = false, payloadHash }) {
  const date = amzDate.slice(0, 8);
  const hashed = payloadHash || await sha256hex(body);
  const h = { host, 'x-amz-date': amzDate };
  for (const [k, v] of Object.entries(headers)) h[k.toLowerCase()] = v;
  if (s3) h['x-amz-content-sha256'] = hashed;
  const names = Object.keys(h).sort();
  const canonHeaders = names.map((n) => n + ':' + String(h[n]).trim().replace(/\s+/g, ' ') + '\n').join('');
  const signedHeaders = names.join(';');
  const canonicalRequest = [method, canonicalPath(path), canonicalQuery(query), canonHeaders, signedHeaders, hashed].join('\n');
  const scope = `${date}/${region}/${service}/aws4_request`;
  const stringToSign = ['AWS4-HMAC-SHA256', amzDate, scope, await sha256hex(canonicalRequest)].join('\n');
  let key = await hmac('AWS4' + secretAccessKey, date);
  key = await hmac(key, region);
  key = await hmac(key, service);
  key = await hmac(key, 'aws4_request');
  const signature = hex(await hmac(key, stringToSign));
  const authorization = `AWS4-HMAC-SHA256 Credential=${accessKeyId}/${scope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  const send = { ...h, authorization };
  delete send.host;
  return { headers: send, canonicalRequest, stringToSign, signature, authorization };
}

export const amzDateOf = (d) => d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');

/* ---- S3's XML ----------------------------------------------------------- */
const unxml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
  .replace(/&apos;/g, "'").replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
  .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCharCode(parseInt(n, 16))).replace(/&amp;/g, '&');
const xmlEsc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
const tag = (block, name) => {
  const m = block.match(new RegExp('<' + name + '>([\\s\\S]*?)</' + name + '>'));
  return m ? unxml(m[1]) : null;
};

/* One page of ListObjectsV2. */
export function parseList(xml) {
  const objects = [];
  for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
    objects.push({ key: tag(m[1], 'Key'), size: Number(tag(m[1], 'Size') || 0), lastModified: tag(m[1], 'LastModified') });
  }
  return { objects, truncated: tag(xml, 'IsTruncated') === 'true', next: tag(xml, 'NextContinuationToken') };
}

/* The body of one DeleteObjects call. Quiet: S3 answers only the failures. */
export function deleteBody(keys) {
  return '<?xml version="1.0" encoding="UTF-8"?><Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Quiet>true</Quiet>' +
    keys.map((k) => '<Object><Key>' + xmlEsc(k) + '</Key></Object>').join('') + '</Delete>';
}

export function parseDeleteResult(xml) {
  const errors = [];
  for (const m of xml.matchAll(/<Error>([\s\S]*?)<\/Error>/g)) {
    errors.push({ key: tag(m[1], 'Key'), code: tag(m[1], 'Code'), message: tag(m[1], 'Message') });
  }
  return { errors };
}

/* ---- The decisions ------------------------------------------------------ */
export const MIN_AGE_DAYS = 7;
export const DEFAULT_MAX = 500;

/**
 * Sorts what was listed. Only a key inside `prefix/` is ever a candidate; a
 * folder marker is skipped; an object younger than seven days (an upload in
 * flight, or one whose row is still being written) is never judged.
 * `inUse` is the set the database answered. Answers four lists.
 */
export function plan({ objects, inUse, now, prefix, minAgeDays = MIN_AGE_DAYS }) {
  const root = prefix.replace(/\/+$/, '') + '/';
  const cutoff = now.getTime() - minAgeDays * 86400000;
  const out = { outside: [], young: [], kept: [], orphans: [] };
  for (const o of objects) {
    if (!o.key || !o.key.startsWith(root) || o.key.endsWith('/') || o.key === root) { out.outside.push(o); continue; }
    const t = Date.parse(o.lastModified);
    if (!Number.isFinite(t) || t > cutoff) { out.young.push(o); continue; }
    (inUse.has(o.key) ? out.kept : out.orphans).push(o);
  }
  return out;
}

/* The keys worth asking the database about: old enough, inside the prefix. */
export const judged = (objects, now, prefix, minAgeDays = MIN_AGE_DAYS) =>
  plan({ objects, inUse: new Set(), now, prefix, minAgeDays }).orphans.map((o) => o.key);

/**
 * Whether this run deletes. A dry run unless S3_SWEEP_DELETE is exactly
 * "on" and the caller did not ask for a dry run. Held, deleting nothing,
 * when the answer looks wrong: more than `max` to go at once, or nothing in
 * use at all while old files exist (a database answering nothing is far
 * likelier than a bucket nobody uses).
 */
export function decide({ kept, orphans, deleteFlag, forceDry = false, max = DEFAULT_MAX }) {
  const on = String(deleteFlag || '').trim() === 'on';
  if (!orphans.length) return { mode: on && !forceDry ? 'delete' : 'dry', reason: 'nothing to delete' };
  if (!kept.length) return { mode: 'held', reason: 'the database named no file in use; nothing deleted' };
  if (orphans.length > max) return { mode: 'held', reason: `${orphans.length} to delete is over the limit of ${max}; nothing deleted` };
  if (!on) return { mode: 'dry', reason: 'dry run (S3_SWEEP_DELETE is not "on")' };
  if (forceDry) return { mode: 'dry', reason: 'dry run asked for' };
  return { mode: 'delete', reason: null };
}

const sum = (list) => list.reduce((n, o) => n + (Number(o.size) || 0), 0);

/* The report row, from the plan, the decision and what the deletes did. */
export function report({ prefix, sorted, decision, deletedKeys = [], failures = [], note = null }) {
  const gone = new Set(deletedKeys);
  const deleted = sorted.orphans.filter((o) => gone.has(o.key));
  const listed = [...sorted.young, ...sorted.kept, ...sorted.orphans];
  return {
    mode: decision.mode,
    prefix,
    listed: listed.length, listed_bytes: sum(listed),
    young: sorted.young.length, young_bytes: sum(sorted.young),
    kept: sorted.kept.length, kept_bytes: sum(sorted.kept),
    would_delete: sorted.orphans.length, would_delete_bytes: sum(sorted.orphans),
    deleted: deleted.length, deleted_bytes: sum(deleted),
    failed: failures.length,
    note: [decision.reason, note, failures.length ? failures.slice(0, 5).map((f) => f.key + ' ' + f.code).join('; ') : null]
      .filter(Boolean).join(' · ') || null,
    sample: sorted.orphans.slice(0, 20).map((o) => o.key)
  };
}

export function chunk(list, n) {
  const out = [];
  for (let i = 0; i < list.length; i += n) out.push(list.slice(i, i + n));
  return out;
}

/* Constant-time comparison of the caller's token with the sweep's own. */
export function sameToken(a, b) {
  const x = enc.encode(String(a || '')), y = enc.encode(String(b || ''));
  if (!y.length || x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}
