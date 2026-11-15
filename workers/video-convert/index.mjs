/*
 * adspace-video-convert (AWS Lambda, Node.js 20).
 *
 * Every video uploaded under content/ gets an H.264 MP4 copy beside it that
 * every browser plays: content/…/name.mov → content/…/name.web.mp4. An
 * iPhone's own file (HEVC in QuickTime) plays only in Safari. The copy is
 * made by AWS Elemental MediaConvert; this function only decides what needs
 * one and asks for it. The pages name the copy first and the original after
 * (js/media.js), so a video plays everywhere as soon as its copy lands.
 *
 * Triggered by the bucket's ObjectCreated events under content/. It never
 * deletes and never overwrites an original: it reads, and MediaConvert
 * writes one new file next to it.
 *
 * Environment:
 *   MC_ROLE_ARN   the role MediaConvert takes to read and write the bucket
 *   AWS_REGION    set by Lambda (the bucket's region, ap-southeast-5)
 *
 * Invoked by hand with { "all": true } it walks content/ once and asks for
 * every copy still missing (the videos uploaded before it existed); with
 * { "all": true, "redo": true } it also asks again for any copy over the
 * cap (1080 × 1920, 60 fps; see logic.mjs). Either walk stops 30 seconds
 * before Lambda's time runs out and answers `next`, the last key reached;
 * run it again with { "all": true, "startAfter": next } to carry on. A video
 * uploaded in the last 30 minutes is left to its own upload trigger. One
 * file that cannot be read or asked for is recorded as `error: …` and the
 * rest go on; an upload trigger never fails, so Lambda never retries it.
 */
import { S3Client, GetObjectCommand, HeadObjectCommand, ListObjectsV2Command } from '@aws-sdk/client-s3';
import * as MC from '@aws-sdk/client-mediaconvert';

import { PREFIX, ISO_BMFF, UNREAD, isCandidate, webKey, codecsIn, videoInfo, overCap, alreadyWeb, jobFor, u32, cc,
  fromProbe, hasAudioOf, attempt, walk } from './logic.mjs';
const { MediaConvertClient, CreateJobCommand } = MC;

const s3 = new S3Client({});
const mc = new MediaConvertClient({});

/* Four-character codes read straight from the file, never the whole file:
   the top-level boxes, then the sample entries of the movie box. */
async function range(Bucket, Key, a, b) {
  const r = await s3.send(new GetObjectCommand({ Bucket, Key, Range: `bytes=${a}-${b}` }));
  return Buffer.from(await r.Body.transformToByteArray());
}
async function inspect(Bucket, Key, size) {
  const boxes = []; let at = 0;
  for (let n = 0; n < 40 && at < size; n++) {
    const h = await range(Bucket, Key, at, Math.min(at + 15, size - 1));
    let len = u32(h, 0); const type = cc(h, 4);
    if (len === 1) len = Number(h.readBigUInt64BE(8));
    if (len === 0) len = size - at;
    boxes.push({ type, at, len });
    if (len < 8) break;
    at += len;
  }
  const moov = boxes.find((b) => b.type === 'moov');
  const mdat = boxes.find((b) => b.type === 'mdat');
  const ftyp = boxes.find((b) => b.type === 'ftyp');
  let brand = '';
  if (ftyp) brand = cc(await range(Bucket, Key, ftyp.at, ftyp.at + 11), 8);
  const whole = moov && moov.len < 64 * 1024 * 1024 ? await range(Bucket, Key, moov.at, moov.at + moov.len - 1) : null;
  return { brand, codecs: whole ? codecsIn(whole) : [], video: whole ? videoInfo(whole) : null,
    faststart: !!(moov && mdat && moov.at < mdat.at) };
}
/* The copy's size in bytes, or null where there is none. */
async function exists(Bucket, Key) {
  try { const h = await s3.send(new HeadObjectCommand({ Bucket, Key })); return h.ContentLength || 0; }
  catch (e) { return null; }
}

/* Null where S3 answers the original is not there (deleted since its
   upload, or a key that never was); any other refusal is thrown, so the
   walk records it. Nothing is asked of MediaConvert for a file that is gone. */
async function present(Bucket, Key) {
  try { const h = await s3.send(new HeadObjectCommand({ Bucket, Key })); return h.ContentLength || 0; }
  catch (e) {
    if (e && (e.name === 'NotFound' || e.name === 'NoSuchKey' || (e.$metadata && e.$metadata.httpStatusCode === 404))) return null;
    throw e;
  }
}

/* With `redo`, a copy made before the cap is asked for again where it is
   over it; MediaConvert writes the new copy under the same name. The
   original is never touched. */
async function convert(Bucket, Key, size, redo) {
  if (!isCandidate(Key)) return 'not a video';
  if (await present(Bucket, Key) === null) return 'error: not found';
  const had = await exists(Bucket, webKey(Key));
  if (had !== null) {
    if (!redo) return 'copy exists';
    if (!overCap((await inspect(Bucket, webKey(Key), had)).video)) return 'copy exists';
  }
  const ext = (Key.match(/\.([a-z0-9]+)$/i) || [])[1] || '';
  /* A damaged or truncated file, or one gone since its trigger, is not read:
     the copy is still asked for as for a file never read. */
  let info = UNREAD;
  if (ISO_BMFF.test(Key)) {
    try { info = await inspect(Bucket, Key, size); }
    catch (e) { console.warn('not read, asked as unread: ' + Key + ': ' + (e && e.message)); info = UNREAD; }
  }
  if (!info.video) {
    const p = await probe(Bucket, Key);
    if (p) info = Object.assign({}, info, p);
  }
  if (had === null && alreadyWeb(ext, info)) return 'already plays everywhere';
  const r = await mc.send(new CreateJobCommand(jobFor(Bucket, Key, hasAudioOf(info), info.video)));
  return (had === null ? 'job ' : 'redo job ') + (r.Job && r.Job.Id);
}

/* MediaConvert's probe, for a size and rate the file itself did not give.
   Null where the SDK has no probe, the role may not ask, or it fails: the
   job then fits the copy inside the cap's square (logic.mjs, jobFor). */
async function probe(Bucket, Key) {
  if (!MC.ProbeCommand) return null;
  try { return fromProbe(await mc.send(new MC.ProbeCommand({ InputFiles: [{ FileUrl: `s3://${Bucket}/${Key}` }] }))); }
  catch (e) { console.warn('probe failed: ' + Key + ': ' + (e && e.message)); return null; }
}

export const handler = async (event, context) => {
  let done = [], next = null;
  if (event && event.all) {
    const Bucket = event.bucket || 'myadspace';
    const remaining = () => (context && context.getRemainingTimeInMillis ? context.getRemainingTimeInMillis() : Infinity);
    const r = await walk({
      startAfter: event.startAfter, now: Date.now(), remaining,
      list: (StartAfter, ContinuationToken) => s3.send(new ListObjectsV2Command({ Bucket, Prefix: PREFIX, StartAfter, ContinuationToken })),
      convert: (Key, size) => convert(Bucket, Key, size, !!event.redo)
    });
    done = r.done; next = r.next;
  } else {
    for (const rec of (event && event.Records) || []) {
      const Bucket = rec.s3.bucket.name;
      const Key = decodeURIComponent(String(rec.s3.object.key).replace(/\+/g, ' '));
      done.push([Key, await attempt(() => convert(Bucket, Key, rec.s3.object.size))]);
    }
  }
  done.forEach(([k, what]) => (/^error: /.test(what) ? console.error : console.log)(what + ': ' + k));
  if (next) console.log('Stopped before the time ran out. Run again with { "all": true, "startAfter": "' + next + '" }.');
  return next ? { done: done.length, results: done, next } : { done: done.length, results: done };
};
