/*
 * s3-sweep/logic.mjs — everything the storage report works out, with no
 * network.
 *
 * Plain JavaScript so the same file runs in the Deno edge function and in
 * the Node suite (tests/s3sweep.js), which checks the signer against AWS's
 * published Signature Version 4 examples and the sorting against every case
 * the brief names. Nothing here fetches, reads a secret or deletes, and
 * since 2026-09-28 there is no delete anywhere in the sweep: every uploaded
 * file is kept (the user: "all these couldnt be deleted or removed").
 */

const enc = new TextEncoder();
const toBytes = (x) => (typeof x === 'string' ? enc.encode(x) : x || new Uint8Array(0));
const hex = (buf) => Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');

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

/* ---- The decisions ------------------------------------------------------ */
export const MIN_AGE_DAYS = 7;

/**
 * Sorts what was listed. Only a key inside `prefix/` is ever judged; a
 * folder marker is skipped; an object younger than seven days (an upload in
 * flight, or one whose row is still being written) is never judged.
 * `inUse` is the set the database answered. Answers four lists.
 */
export function plan({ objects, inUse, now, prefix, minAgeDays = MIN_AGE_DAYS }) {
  const root = prefix.replace(/\/+$/, '') + '/';
  const cutoff = now.getTime() - minAgeDays * 86400000;
  const out = { outside: [], young: [], kept: [], orphans: [] };
  /* A video's playable copy (name.web.mp4, workers/video-convert/) is in use
     while its original is: no row names the copy itself. */
  const bases = new Set();
  inUse.forEach((k) => bases.add(String(k).replace(/\.[^./]+$/, '')));
  const used = (k) => inUse.has(k) || (/\.web\.mp4$/i.test(k) && bases.has(k.replace(/\.web\.mp4$/i, '')));
  for (const o of objects) {
    if (!o.key || !o.key.startsWith(root) || o.key.endsWith('/') || o.key === root) { out.outside.push(o); continue; }
    const t = Date.parse(o.lastModified);
    if (!Number.isFinite(t) || t > cutoff) { out.young.push(o); continue; }
    (used(o.key) ? out.kept : out.orphans).push(o);
  }
  return out;
}

/* The keys worth asking the database about: old enough, inside the prefix. */
export const judged = (objects, now, prefix, minAgeDays = MIN_AGE_DAYS) =>
  plan({ objects, inUse: new Set(), now, prefix, minAgeDays }).orphans.map((o) => o.key);

/**
 * What kind of report this run files. Every run is a report (`dry`): the
 * sweep has no way to delete. It reads `held` when the answer looks wrong,
 * old files present and the database naming none of them in use (a database
 * answering nothing is far likelier than a bucket nobody uses), so the count
 * of unused files is not trusted that day.
 */
export function decide({ kept, orphans }) {
  if (orphans.length && !kept.length) return { mode: 'held', reason: 'the database named no file in use; the count of unused files is not trusted' };
  return { mode: 'dry', reason: 'report only; the sweep never deletes' };
}

const sum = (list) => list.reduce((n, o) => n + (Number(o.size) || 0), 0);

/* The report row, from the plan and the decision. `would_delete` counts the
   files no row names; nothing is ever deleted, so `deleted` stays 0. */
export function report({ prefix, sorted, decision }) {
  const listed = [...sorted.young, ...sorted.kept, ...sorted.orphans];
  return {
    mode: decision.mode,
    prefix,
    listed: listed.length, listed_bytes: sum(listed),
    young: sorted.young.length, young_bytes: sum(sorted.young),
    kept: sorted.kept.length, kept_bytes: sum(sorted.kept),
    would_delete: sorted.orphans.length, would_delete_bytes: sum(sorted.orphans),
    deleted: 0, deleted_bytes: 0,
    failed: 0,
    note: decision.reason || null,
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
